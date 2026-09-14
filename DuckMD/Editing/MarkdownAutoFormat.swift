import AppKit

/// Умное автоформатирование Markdown в редакторе:
///
/// - Enter в элементе списка → новый пункт (с авто-удалением пустого пункта)
/// - Ввод `# `/`## `/... в начале строки → заголовок
/// - Ввод `- `/`* `/`+ ` в начале строки → маркированный список
/// - Ввод `1. ` в начале строки → нумерованный список
/// - Ввод `> ` в начале строки → цитата
/// - Авто-закрытие парных символов: ** * ` ~~ _ (превращаются в **|** с курсором внутри)
/// - Tab/Shift-Tab в списке → отступ/отмена отступа
///
/// Действует как делегат-перехватчик клавиш NSTextView.
final class MarkdownAutoFormatter: NSObject, NSTextViewDelegate {
    weak var nextDelegate: NSTextViewDelegate?
    weak var textView: NSTextView?

    init(nextDelegate: NSTextViewDelegate?) {
        self.nextDelegate = nextDelegate
    }

    // MARK: - Клавишные перехваты

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        self.textView = textView
        guard SettingsStore.shared.autoformatEnabled else {
            return nextDelegate?.textView?(textView, doCommandBy: commandSelector) ?? false
        }
        
        // Enter (вставка новой строки) — обрабатываем автопродолжение списков
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if handleListContinuation(in: textView) { return true }
        }
        // Tab — отступ элемента списка вправо
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            if handleIndent(in: textView, outdent: false) { return true }
        }
        // Shift-Tab — отступ влево
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            if handleIndent(in: textView, outdent: true) { return true }
        }
        return nextDelegate?.textView?(textView, doCommandBy: commandSelector) ?? false
    }

    // MARK: - Перехват вставки текста (для авто-закрытия и триггеров префиксов)

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange,
                  replacementString: String?) -> Bool {
        self.textView = textView
        guard let replacement = replacementString else { return true }

        // Авто-закрытие парных символов
        if SettingsStore.shared.autoClosePairs, let closed = Self.pairedClose(for: replacement) {
            return insertPaired(textView, in: affectedCharRange, open: replacement, close: closed)
        }

        // Триггеры префиксов на пустой строке: `#`, `-`, `*`, `>`, `1.` и т.д.
        if SettingsStore.shared.autoformatEnabled, replacement == " " {
            if handlePrefixTrigger(textView, in: affectedCharRange) { return false }
        }

        return nextDelegate?.textView?(textView, shouldChangeTextIn: affectedCharRange, replacementString: replacementString) ?? true
    }

    // Прокси остальных делегатных методов — чтобы coordinator получил textDidChange.
    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || nextDelegate?.responds(to: aSelector) == true
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if nextDelegate?.responds(to: aSelector) == true { return nextDelegate }
        return super.forwardingTarget(for: aSelector)
    }

    // MARK: - Продолжение списка по Enter

    /// Если курсор в элементе списка и строка пункта пустая — удаляем маркер.
    /// Если в пункте есть текст — добавляем новый пункт с маркером.
    private func handleListContinuation(in textView: NSTextView) -> Bool {
        let (lineRange, line) = currentLine(in: textView)
        guard let marker = listMarker(of: line) else { return false }

        // Текст пункта после маркера
        let content = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)

        if content.isEmpty {
            // Пустой пункт → удаляем маркер (выходим из списка)
            textView.replaceCharacters(in: lineRange, with: "")
            return false // позволяем стандартный Enter (новая строка)
        }

        // Продолжаем список: вставляем перенос + маркер
        let nextMarker = incrementedMarker(marker)
        let insertion = "\n\(nextMarker)"
        let cursor = NSMaxRange(lineRange)
        textView.replaceCharacters(in: NSRange(location: cursor, length: 0), with: insertion)
        // Ставим курсор после маркера
        let newCursor = cursor + insertion.count
        textView.selectedRange = NSRange(location: newCursor, length: 0)
        return true
    }

    // MARK: - Tab / Shift-Tab — отступ списка

    private func handleIndent(in textView: NSTextView, outdent: Bool) -> Bool {
        let (lineRange, line) = currentLine(in: textView)
        guard listMarker(of: line) != nil || outdent else { return false }

        if outdent {
            // Снимаем до 2 пробелов/1 таба в начале
            var removeCount = 0
            if line.hasPrefix("    ") { removeCount = 4 }
            else if line.hasPrefix("  ") { removeCount = 2 }
            else if line.hasPrefix("\t") { removeCount = 1 }
            guard removeCount > 0 else { return false }
            textView.replaceCharacters(in: NSRange(location: lineRange.location, length: removeCount), with: "")
        } else {
            // Добавляем отступ
            textView.replaceCharacters(in: NSRange(location: lineRange.location, length: 0), with: "  ")
        }
        return true
    }

    // MARK: - Авто-закрытие пар

    private func insertPaired(_ textView: NSTextView, in range: NSRange, open: String, close: String) -> Bool {
        // Если выделен текст — оборачиваем его (bold/italic/code/strike)
        if range.length > 0 {
            let ns = textView.string as NSString
            let selected = ns.substring(with: range)
            let wrapped = open + selected + close
            textView.replaceCharacters(in: range, with: wrapped)
            textView.selectedRange = NSRange(location: range.location + open.count, length: selected.count)
            return false
        }
        // Иначе вставляем пару и ставим курсор между
        let pair = open + close
        textView.replaceCharacters(in: range, with: pair)
        textView.selectedRange = NSRange(location: range.location + open.count, length: 0)
        return false
    }

    // MARK: - Триггеры префиксов

    /// Если пользователь ввёл слово+пробел в начале строки, и это маркер Markdown — превращаем.
    private func handlePrefixTrigger(_ textView: NSTextView, in range: NSRange) -> Bool {
        let (lineRange, line) = currentLine(in: textView)

        // Проверяем: курсор в конце строки, префикс совпадает с маркером
        let cursorAtEnd = range.location >= NSMaxRange(lineRange) - 1
        guard cursorAtEnd else { return false }

        let trimmedStart = line.trimmingCharacters(in: .whitespaces)
        let leadingWS = line.countingLeadingWhitespace

        // Заголовки
        if let level = headingPrefixLevel(trimmedStart) {
            // Превращаем `## ` — уже есть пробел, ничего не делаем если уже отформатировано
            if trimmedStart == String(repeating: "#", count: level) {
                apply(textView, in: lineRange, replacement: String(repeating: "#", count: level) + " ", leadingWS: leadingWS)
                return true
            }
        }
        // Маркеры списка / цитата
        let triggers: [String] = ["-", "*", "+", ">", "·"]
        if triggers.contains(trimmedStart), trimmedStart.count == 1 {
            // Уже добавили пробел? Нет — заменяем триггер на `маркер `
            apply(textView, in: lineRange, replacement: "\(trimmedStart) ", leadingWS: leadingWS)
            return true
        }
        // Нумерованный список: `1`, `12` + `.` + пробел
        if trimmedStart.hasSuffix("."), trimmedStart.dropLast().allSatisfy(\.isNumber) {
            apply(textView, in: lineRange, replacement: "\(trimmedStart) ", leadingWS: leadingWS)
            return true
        }
        return false
    }

    private func apply(_ textView: NSTextView, in lineRange: NSRange, replacement: String, leadingWS: Int) {
        let ws = String(repeating: " ", count: leadingWS)
        textView.replaceCharacters(in: lineRange, with: ws + replacement + "")
        // Курсор — в конец строки
        let newLen = (ws + replacement).count
        textView.selectedRange = NSRange(location: lineRange.location + newLen, length: 0)
    }

    // MARK: - Helpers

    private func currentLine(in textView: NSTextView) -> (NSRange, String) {
        let ns = textView.string as NSString
        let cursor = textView.selectedRange.location
        let lineRange = ns.lineRange(for: NSRange(location: cursor, length: 0))
        let line = ns.substring(with: lineRange)
        return (lineRange, line)
    }

    // MARK: - Кэш regex (Этап 3)

    /// Этап 3: раньше `range(of:options:.regularExpression)` компилировал
    /// NSRegularExpression на каждый Enter — теперь паттерны создаются один раз.
    private static let orderedMarkerRegex = try? NSRegularExpression(pattern: #"^(\d+)\.\ "#)
    private static let orderedMarkerCaptureRegex = try? NSRegularExpression(pattern: #"^(\d+)\.\ "#)

    private func listMarker(of line: String) -> String? {
        let trimmed = line.drop(while: { $0 == " " })
        // Маркированный
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return String(trimmed.prefix(2))
        }
        // Чек-бокс
        if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            return String(trimmed.prefix(6))
        }
        // Нумерованный — по закэшированному regex
        guard let regex = Self.orderedMarkerRegex else { return nil }
        let s = String(trimmed)
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (s as NSString).substring(with: m.range)
    }

    private func incrementedMarker(_ marker: String) -> String {
        // `1. ` → `2. `, `5. ` → `6. `
        guard let regex = Self.orderedMarkerCaptureRegex else { return marker }
        let ns = marker as NSString
        guard let m = regex.firstMatch(in: marker, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return marker }
        let digits = ns.substring(with: m.range(at: 1))
        if let n = Int(digits) {
            return "\(n + 1). "
        }
        return marker
    }

    private func headingPrefixLevel(_ s: String) -> Int? {
        var count = 0
        for ch in s { if ch == "#" { count += 1 } else { break } }
        return (1...6).contains(count) ? count : nil
    }

    // MARK: - Пары

    private static func pairedClose(for open: String) -> String? {
        switch open {
        case "**": return "**"
        case "*": return "*"
        case "`": return "`"
        case "~~": return "~~"
        case "_": return "_"
        case "(": return ")"
        case "[": return "]"
        case "{": return "}"
        default: return nil
        }
    }
}

private extension String {
    var countingLeadingWhitespace: Int {
        var n = 0
        for ch in self {
            if ch == " " || ch == "\t" { n += 1 } else { break }
        }
        return n
    }
}
