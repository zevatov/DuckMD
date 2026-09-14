import AppKit

// MARK: - Highlighter

/// Простейший, но читаемый Markdown-хайлайтер для редактора:
/// заголовки, жирный/курсив/зачёркнутый, inline-код, цитаты, ссылки, списки, код-блоки.
/// Вынесен из CodeEditorView.swift (R8): относится к Editing-слою.
enum MarkdownHighlighter {
    static func highlight(_ source: String) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: source)
        let fontSize = CGFloat(SettingsStore.shared.editorFontSize)
        let base: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]
        attr.addAttributes(base, range: NSRange(location: 0, length: attr.length))

        let lines = source.components(separatedBy: "\n")
        var location = 0
        for line in lines {
            let range = NSRange(location: location, length: line.utf16.count)
            highlightLine(attr, line: line, range: range)
            location += line.utf16.count + 1 // +1 за \n
        }
        return attr
    }

    private static func highlightLine(_ attr: NSMutableAttributedString, line: String, range: NSRange) {
        let heading = Color.heading
        let marker = Color.marker
        let symbol = Color.symbol
        let emphasis = Color.emphasis
        let code = Color.code
        let string = Color.string

        // Код-блок ``` или ~~~
        if line.hasPrefix("```") || line.hasPrefix("~~~") {
            let fontSize = CGFloat(SettingsStore.shared.editorFontSize) - 1
            attr.addAttributes([.foregroundColor: code, .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)],
                               range: range)
            return
        }
        // Заголовки
        if let lvl = headingLevel(line) {
            let fontSize = CGFloat(SettingsStore.shared.editorFontSize)
            attr.addAttributes([.foregroundColor: heading,
                                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)],
                               range: range)
            // Маркеры `#` чуть тусклее
            attr.addAttributes([.foregroundColor: marker],
                               range: NSRange(location: range.location, length: lvl))
            return
        }
        // Цитаты
        if line.hasPrefix(">") {
            attr.addAttributes([.foregroundColor: marker], range: range)
            return
        }
        // Списки / todo
        if isListItem(line), let m = listMarkerLength(line) {
            attr.addAttributes([.foregroundColor: marker],
                               range: NSRange(location: range.location, length: m))
        }
        // Inline: код в `...`, **bold**, *italic*, ~~strike~~, [text](url)
        let inlineColors = InlineColors(symbol: symbol, emphasis: emphasis, code: code, string: string)
        applyInline(attr, line: line, range: range, colors: inlineColors)
    }

    private static func headingLevel(_ line: String) -> Int? {
        var count = 0
        for ch in line {
            if ch == "#" { count += 1 } else { break }
        }
        if count > 0 && count <= 6 && line.count > count && line[line.index(line.startIndex, offsetBy: count)] == " " {
            return count
        }
        return nil
    }

    // MARK: - Кэш regex (Этап 3)

    /// Этап 3: скомпилированные паттерны создаются один раз — раньше
    /// NSRegularExpression компилировался на КАЖДУЮ строку документа (× 5
    /// inline-паттернов + 2 list-паттерна), что доминировало в профиле
    /// подсветки больших файлов.
    private static let orderedListRegex = try? NSRegularExpression(pattern: #"^\d+\.\ "#)
    private static let listMarkerRegex = try? NSRegularExpression(pattern: #"^\s*(-|\*|\+|\d+\.)\s*(\[[ xX]\]\s+)?"#)
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: #"`[^`\n]+`"#)
    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*[^*\n]+\*\*"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*[^*\n]+\*(?!\*)"#)
    private static let strikeRegex = try? NSRegularExpression(pattern: #"~~[^~\n]+~~"#)
    private static let linkRegex = try? NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\n]+)\)"#)

    /// Юнит-тест: все паттерны должны компилироваться при загрузке.
    static var cachedRegexesAreValid: Bool {
        orderedListRegex != nil && listMarkerRegex != nil && inlineCodeRegex != nil &&
        boldRegex != nil && italicRegex != nil && strikeRegex != nil && linkRegex != nil
    }

    /// Этап 3: матчинг по закэшированному NSRegularExpression (utf16-смещения).
    /// nil-regex (некорректный паттерн — теоретически) даёт пустой список.
    private static func matches(_ regex: NSRegularExpression?, in line: String) -> [NSTextCheckingResult] {
        guard let regex else { return [] }
        let ns = line as NSString
        return regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
    }

    private static func isListItem(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") { return true }
        if t.hasPrefix("- [") || t.hasPrefix("* [") { return true }
        guard let regex = orderedListRegex else { return false }
        let ns = t as NSString
        return regex.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func listMarkerLength(_ line: String) -> Int? {
        guard let regex = listMarkerRegex else { return nil }
        let ns = line as NSString
        guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              m.range.length > 0 else { return nil }
        return m.range.location + m.range.length
    }

    private static func applyInline(_ attr: NSMutableAttributedString, line: String, range: NSRange, colors: InlineColors) {
        // Этап 3: все паттерны — из статического кэша (без перекомпиляции).
        // Inline code `...`
        for m in matches(inlineCodeRegex, in: line) {
            attr.addAttributes([.foregroundColor: colors.code], range: offset(m, base: range))
        }
        // **bold**
        for m in matches(boldRegex, in: line) {
            let fontSize = CGFloat(SettingsStore.shared.editorFontSize)
            attr.addAttributes([.foregroundColor: colors.emphasis,
                                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .bold)],
                               range: offset(m, base: range))
        }
        // *italic*
        for m in matches(italicRegex, in: line) {
            attr.addAttributes([.foregroundColor: colors.emphasis, .font: italicFont()],
                               range: offset(m, base: range))
        }
        // ~~strike~~
        for m in matches(strikeRegex, in: line) {
            attr.addAttributes([.foregroundColor: colors.emphasis,
                                .strikethroughStyle: NSUnderlineStyle.single.rawValue],
                               range: offset(m, base: range))
        }
        // [text](url)
        for m in matches(linkRegex, in: line) {
            attr.addAttributes([.foregroundColor: colors.string], range: offset(m, base: range))
        }
    }

    /// Сдвигает range совпадения на смещение начала строки в полном тексте.
    /// У NSTextCheckingResult в regex-сценарии нужно использовать `.range`, а не `.location`/`.length`.
    private static func offset(_ match: NSTextCheckingResult, base: NSRange) -> NSRange {
        NSRange(location: base.location + match.range.location, length: match.range.length)
    }

    /// Курсивный моноширинный шрифт (через descriptor symbolic traits — NSFont не имеет withSymbolicTraits).
    private static func italicFont() -> NSFont {
        let fontSize = CGFloat(SettingsStore.shared.editorFontSize)
        let base = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let descriptor = base.fontDescriptor.withSymbolicTraits([.italic])
        return NSFont(descriptor: descriptor, size: fontSize) ?? base
    }

    private struct InlineColors {
        let symbol: NSColor
        let emphasis: NSColor
        let code: NSColor
        let string: NSColor
    }

    enum Color {
        static let heading = NSColor(red: 0.96, green: 0.62, blue: 0.07, alpha: 1.0)
        static let marker = NSColor.systemOrange
        static let symbol = NSColor.systemBlue
        static let emphasis = NSColor.systemPink
        static let code = NSColor.systemTeal
        static let string = NSColor.systemGreen
    }
}
