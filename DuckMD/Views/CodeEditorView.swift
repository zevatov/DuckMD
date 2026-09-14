import SwiftUI
import AppKit

/// Клип-вью с гарантированной блокировкой горизонтального скролла.
/// Исключает смещение текста влево/вправо и обрезание начала строк при жестах трекпада.
/// Учитывает наличие вертикального ruler'а (габариты номеров строк), фиксируя origin.x точно на базовой линии.
final class LockedHorizontalClipView: NSClipView {
    /// Базовый origin.x для клип-вью:
    /// Когда включен вертикальный ruler, AppKit располагает documentView на x = 0,
    /// а bounds.origin.x клип-вью должен быть -ruleThickness, чтобы текст начинался сразу справа от линейки.
    /// Без линейки базовый origin.x равен 0.
    var baseOriginX: CGFloat {
        if let scrollView = enclosingScrollView, scrollView.rulersVisible, let ruler = scrollView.verticalRulerView {
            return -ruler.ruleThickness
        }
        return 0
    }

    override var bounds: NSRect {
        get { super.bounds }
        set {
            var rect = newValue
            rect.origin.x = baseOriginX
            super.bounds = rect
        }
    }

    override func setBoundsOrigin(_ newOrigin: NSPoint) {
        super.setBoundsOrigin(NSPoint(x: baseOriginX, y: newOrigin.y))
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        rect.origin.x = baseOriginX
        return rect
    }

    override func scroll(to newOrigin: NSPoint) {
        super.scroll(to: NSPoint(x: baseOriginX, y: newOrigin.y))
    }
}

/// Нативный редактор кода на базе NSTextView с подсветкой синтаксиса Markdown.
/// Двусторонний скролл: отдаёт позицию через callback И принимает от превью.
struct CodeEditorView: NSViewRepresentable {
    @Binding var text: String
    /// Входящая дробь скролла от превью (0...1)
    var scrollFraction: CGFloat = 0
    /// Позиция скролла (строка, следующая строка, смещение, общая дробь) для центрированного скролла
    var scrollPosition: (line: Int, nextLine: Int?, offset: CGFloat, fraction: CGFloat)? = nil
    /// Включена ли синхронизация скролла
    var syncScroll: Bool = false
    /// Активная линия для синхронизации выделения (1-индексированная)
    var activeLine: Int = 1
    /// Диапазон строк для подсветки активного блока (1-индексированный)
    var highlightedLineRange: ClosedRange<Int>? = nil
    /// Callback: передаёт долю скролла 0...1 при пользовательской прокрутке
    var onScrollFractionChanged: ((CGFloat) -> Void)? = nil
    /// Callback: передаёт строку, смещение и общую дробь при пользовательской прокрутке
    var onScrollPositionChanged: ((Int, CGFloat, CGFloat) -> Void)? = nil
    /// Callback: передаёт 1-индексированный номер строки и колонку (если таблица) при изменении позиции курсора
    var onCursorLineChanged: ((Int, Int?) -> Void)? = nil
    /// Этап 1.3: внешний текст не применён, потому что пользователь редактирует
    /// (firstResponder). Аргументы: (новый текст модели, текущий текст редактора).
    /// Владелец ставит внешний текст в очередь вместо тихого пропуска.
    var onPendingExternalText: ((String, String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = MarkdownTextView()
        // Авто-форматтер становится делегатом; он проксирует textDidChange в coordinator.
        let formatter = MarkdownAutoFormatter(nextDelegate: context.coordinator)
        context.coordinator.formatter = formatter
        textView.delegate = formatter
        textView.string = text
        textView.highlight()

        let scrollView = NSScrollView()
        let clipView = LockedHorizontalClipView()
        clipView.drawsBackground = false
        scrollView.contentView = clipView
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.hasHorizontalRuler = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        scrollView.drawsBackground = false

        // Счётчик строк (ruler)
        let rulerView = LineNumberRulerView(textView: textView)
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = rulerView
        scrollView.rulersVisible = SettingsStore.shared.showLineNumbers
        context.coordinator.rulerView = rulerView

        // Подписываемся на скролл
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        context.coordinator.scrollView = scrollView

        // Обновлять ruler при изменении текста
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.textStorageDidProcess(_:)),
            name: NSTextStorage.didProcessEditingNotification,
            object: textView.textStorage
        )

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? MarkdownTextView else { return }
        
        let currentFontSize = CGFloat(SettingsStore.shared.editorFontSize)
        if textView.font?.pointSize != currentFontSize {
            textView.font = NSFont.monospacedSystemFont(ofSize: currentFontSize, weight: .regular)
            textView.highlight()
        }

        // Обновляем только если текст изменился ИЗВНЕ (FileWatcher, undo и т.д.).
        // Если пользователь сейчас печатает (firstResponder), НЕ пропускаем тихо:
        // уведомляем владельца — он ставит внешний текст в очередь (merge-баннер),
        // иначе внешний контент терялся бы при следующей клавише.
        let isEditing = textView.window?.firstResponder === textView
        if textView.string != text {
            if isEditing {
                onPendingExternalText?(text, textView.string)
            } else {
                let selected = textView.selectedRange()
                textView.string = text
                textView.setSelectedRange(NSRange(location: min(selected.location, textView.string.count), length: 0))
                textView.highlight()
            }
        }
        
        // Обновляем подсветку активного блока
        if textView.highlightedLineRange != highlightedLineRange {
            textView.highlightedLineRange = highlightedLineRange
        }

        // Принимаем активную строку от превью/модели
        if context.coordinator.lastAppliedActiveLine != activeLine {
            context.coordinator.lastAppliedActiveLine = activeLine
            context.coordinator.lastReportedLine = activeLine
            
            let index = context.coordinator.lineCache.characterIndex(for: activeLine)
            textView.setSelectedRange(NSRange(location: index, length: 0))
            
            if let layoutManager = textView.layoutManager,
               let textContainer = textView.textContainer,
               let scrollView = textView.enclosingScrollView {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: index, length: 0), actualCharacterRange: nil)
                let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let inset = textView.textContainerInset.height
                let y = rect.origin.y + inset
                let visibleHeight = scrollView.contentView.bounds.height
                let centeredY = y - (visibleHeight - rect.height) / 2
                let contentHeight = scrollView.documentView?.bounds.height ?? 0
                let maxScroll = contentHeight - visibleHeight
                let targetY = min(max(0, centeredY), max(0, maxScroll))
                
                context.coordinator.isProgrammaticScroll = true
                context.coordinator.programmaticScrollTimer?.invalidate()
                let baseX = (scrollView.contentView as? LockedHorizontalClipView)?.baseOriginX ?? 0
                scrollView.contentView.scroll(to: NSPoint(x: baseX, y: targetY))
                scrollView.reflectScrolledClipView(scrollView.contentView)
                
                context.coordinator.programmaticScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak coordinator = context.coordinator] _ in
                    coordinator?.isProgrammaticScroll = false
                }
            } else {
                textView.scrollRangeToVisible(NSRange(location: index, length: 0))
            }
        }

        // Принимаем скролл от превью
        if syncScroll {
            let inResize = nsView.window?.inLiveResize ?? false
            if !inResize {
                if let pos = scrollPosition {
                    let posChanged = context.coordinator.lastAppliedPosition?.line != pos.line ||
                                     context.coordinator.lastAppliedPosition?.nextLine != pos.nextLine ||
                                     abs((context.coordinator.lastAppliedPosition?.offset ?? 0) - pos.offset) > 0.01 ||
                                     abs((context.coordinator.lastAppliedPosition?.fraction ?? 0) - pos.fraction) > 0.001
                    if posChanged {
                        context.coordinator.lastAppliedPosition = pos
                        context.coordinator.lastAppliedFraction = pos.fraction
                        context.coordinator.scrollToPosition(line: pos.line, nextLine: pos.nextLine, offset: pos.offset, fraction: pos.fraction)
                    }
                } else if abs(context.coordinator.lastAppliedFraction - scrollFraction) > 0.0001 {
                    context.coordinator.lastAppliedFraction = scrollFraction
                    context.coordinator.scrollToFraction(scrollFraction)
                }
            }
        }
        
        let showLineNumbers = SettingsStore.shared.showLineNumbers
        if nsView.rulersVisible != showLineNumbers {
            nsView.rulersVisible = showLineNumbers
        }
        
        context.coordinator.parent = self
    }

    /// SwiftUI вызывает при демонтаже view: снимаем selector-based наблюдателей,
    /// иначе Coordinator остаётся в NotificationCenter (утечка).
    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        let center = NotificationCenter.default
        center.removeObserver(coordinator, name: NSView.boundsDidChangeNotification, object: nil)
        center.removeObserver(coordinator, name: NSTextStorage.didProcessEditingNotification, object: nil)
        coordinator.cancelPendingWork()
    }

/// Быстрый кэш переносов строк: бинарный поиск строки за O(log K) и поиск смещения за O(1)
final class LineIndexCache {
    private(set) var lineStarts: [Int] = [0]
    private var lastLength: Int = -1

    func update(text: String) {
        let ns = text as NSString
        let len = ns.length
        if len == lastLength && !lineStarts.isEmpty { return }
        lastLength = len
        var starts: [Int] = [0]
        for i in 0..<len {
            if ns.character(at: i) == 10 { // \n
                starts.append(i + 1)
            }
        }
        lineStarts = starts
    }

    func line(for charIndex: Int) -> Int {
        var low = 0
        var high = lineStarts.count - 1
        var result = 1
        while low <= high {
            let mid = (low + high) / 2
            if lineStarts[mid] <= charIndex {
                result = mid + 1
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    func characterIndex(for line: Int) -> Int {
        let idx = line - 1
        if idx <= 0 { return 0 }
        if idx < lineStarts.count { return lineStarts[idx] }
        return lineStarts.last ?? 0
    }
}

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditorView
        var formatter: MarkdownAutoFormatter?
        weak var scrollView: NSScrollView?
        weak var rulerView: LineNumberRulerView?
        private var highlightWork: DispatchWorkItem?
        var programmaticScrollTimer: Timer?
        var lineCache = LineIndexCache()
        /// Последняя применённая входящая дробь (для дедупликации updateNSView)
        var lastAppliedFraction: CGFloat = 0
        /// Последняя применённая позиция (строка, следующая строка, смещение, дробь)
        var lastAppliedPosition: (line: Int, nextLine: Int?, offset: CGFloat, fraction: CGFloat)? = nil
        /// Для дедупликации исходящих callback'ов
        private var lastReportedFraction: CGFloat = -1
        /// Флаг: сейчас скроллим программно (от превью) — не слать callback
        var isProgrammaticScroll = false
        /// Последняя применённая входящая активная строка
        var lastAppliedActiveLine: Int = 1
        /// Последняя отправленная активная строка
        var lastReportedLine: Int = -1
        var lastReportedCol: Int? = nil

        init(_ parent: CodeEditorView) {
            self.parent = parent
            lineCache.update(text: parent.text)
        }

        /// Отмена отложенных работ (вызывается из dismantleNSView при демонтаже view)
        func cancelPendingWork() {
            highlightWork?.cancel()
            programmaticScrollTimer?.invalidate()
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let newValue = textView.string
            lineCache.update(text: newValue)
            
            // Синхронно обновляем Binding модели, чтобы избежать рассинхронизации
            parent.text = newValue
            
            // Дебаунсим тяжелую подсветку синтаксиса на 150мс
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                (textView as? MarkdownTextView)?.highlight()
                self?.rulerView?.needsDisplay = true
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()
            let text = textView.string
            lineCache.update(text: text)
            
            let nsText = text as NSString
            let safeLocation = min(range.location, nsText.length)
            let line = lineCache.line(for: safeLocation)
            
            // Вычисляем индекс колонки, если мы внутри строки таблицы
            var colIndex: Int? = nil
            let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
            let fullLineText = nsText.substring(with: lineRange)
            let trimmedLine = fullLineText.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine.hasPrefix("|") || trimmedLine.contains("|") {
                let startOfLine = lineRange.location
                let cursorOffsetInLine = safeLocation - startOfLine
                let lineTextBeforeCursor = nsText.substring(with: NSRange(location: startOfLine, length: cursorOffsetInLine))
                let pipeCount = lineTextBeforeCursor.filter { $0 == "|" }.count
                let hasLeadingPipe = trimmedLine.hasPrefix("|")
                colIndex = hasLeadingPipe ? max(0, pipeCount - 1) : pipeCount
            }
            
            if lastReportedLine != line || lastReportedCol != colIndex {
                lastReportedLine = line
                lastReportedCol = colIndex
                lastAppliedActiveLine = line
                parent.onCursorLineChanged?(line, colIndex)
            }
        }

        @objc func textStorageDidProcess(_ notification: Notification) {
            rulerView?.needsDisplay = true
        }

        @objc func scrollViewDidScroll(_ notification: Notification) {
            // Обновляем ruler при скролле
            rulerView?.needsDisplay = true

            // Если скролл программный (от превью) — не слать callback обратно
            if isProgrammaticScroll { return }

            guard let scrollView = scrollView,
                  let documentView = scrollView.documentView,
                  let textView = documentView as? MarkdownTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let visibleHeight = scrollView.contentView.bounds.height
            let contentHeight = documentView.bounds.height - visibleHeight
            guard contentHeight > 0 else { return }

            let currentY = scrollView.contentView.bounds.origin.y
            let fraction = currentY / contentHeight
            let clamped = min(max(fraction, 0), 1)

            // Граничные положения (жесткая доводка)
            if currentY <= 4 {
                lastReportedFraction = 0
                parent.onScrollPositionChanged?(1, 0, 0)
                parent.onScrollFractionChanged?(0)
                return
            }
            if currentY >= contentHeight - 4 {
                lastReportedFraction = 1
                let totalLines = max(1, lineCache.lineStarts.count)
                parent.onScrollPositionChanged?(totalLines, 1, 1)
                parent.onScrollFractionChanged?(1)
                return
            }

            // Ищем строку по центру видимой области за O(log K) вместо O(N)
            let centerY = currentY + visibleHeight / 2
            let pointInContainer = NSPoint(x: 10, y: max(0, centerY - textView.textContainerInset.height))
            let glyphIndex = layoutManager.glyphIndex(for: pointInContainer, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            lineCache.update(text: textView.string)
            let safeChar = min(charIndex, (textView.string as NSString).length)
            let lineNum = lineCache.line(for: safeChar)

            var lineFraction: CGFloat = 0
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            if lineRect.height > 0 {
                let relativeY = pointInContainer.y - lineRect.origin.y
                lineFraction = min(max(relativeY / lineRect.height, 0), 1)
            }

            lastReportedFraction = clamped
            parent.onScrollPositionChanged?(lineNum, lineFraction, clamped)
            parent.onScrollFractionChanged?(clamped)
        }

        /// Центрированный скролл от превью по строке, следующей строке и относительному смещению
        func scrollToPosition(line: Int, nextLine: Int?, offset: CGFloat, fraction: CGFloat) {
            guard let scrollView = scrollView,
                  let documentView = scrollView.documentView,
                  let textView = documentView as? MarkdownTextView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let visibleHeight = scrollView.contentView.bounds.height
            let maxScroll = max(0, documentView.bounds.height - visibleHeight)
            guard maxScroll > 0 else { return }

            var targetY: CGFloat = 0
            if fraction <= 0.005 {
                targetY = 0
            } else if fraction >= 0.995 {
                targetY = maxScroll
            } else {
                lineCache.update(text: textView.string)
                let charIndex1 = lineCache.characterIndex(for: line)
                let glyphRange1 = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex1, length: 0), actualCharacterRange: nil)
                let lineRect1 = layoutManager.boundingRect(forGlyphRange: glyphRange1, in: textContainer)
                let y1 = lineRect1.origin.y + textView.textContainerInset.height

                let y2: CGFloat
                if let nextLine = nextLine, nextLine > line {
                    let charIndex2 = lineCache.characterIndex(for: nextLine)
                    let glyphRange2 = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex2, length: 0), actualCharacterRange: nil)
                    let lineRect2 = layoutManager.boundingRect(forGlyphRange: glyphRange2, in: textContainer)
                    y2 = lineRect2.origin.y + textView.textContainerInset.height
                } else {
                    y2 = min(documentView.bounds.height, y1 + max(lineRect1.height, 20))
                }

                let interpolatedY = y1 + (y2 - y1) * offset
                let centeredY = interpolatedY - visibleHeight / 2
                targetY = min(max(0, centeredY), maxScroll)
            }

            let currentY = scrollView.contentView.bounds.origin.y
            guard abs(currentY - targetY) > 0.5 else { return }

            isProgrammaticScroll = true
            programmaticScrollTimer?.invalidate()

            let baseX = (scrollView.contentView as? LockedHorizontalClipView)?.baseOriginX ?? 0
            scrollView.contentView.scroll(to: NSPoint(x: baseX, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)

            programmaticScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                self?.isProgrammaticScroll = false
            }
        }

        /// Программный скролл от превью — с защитой от echo через isProgrammaticScroll
        func scrollToFraction(_ fraction: CGFloat) {
            guard let scrollView = scrollView,
                  let documentView = scrollView.documentView else { return }
            let contentHeight = documentView.bounds.height - scrollView.contentView.bounds.height
            guard contentHeight > 0 else { return }
            let y = fraction * contentHeight
            
            let currentY = scrollView.contentView.bounds.origin.y
            guard abs(currentY - y) > 0.5 else { return }
            
            isProgrammaticScroll = true
            programmaticScrollTimer?.invalidate()
            
            let baseX = (scrollView.contentView as? LockedHorizontalClipView)?.baseOriginX ?? 0
            scrollView.contentView.scroll(to: NSPoint(x: baseX, y: y))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            
            programmaticScrollTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { [weak self] _ in
                self?.isProgrammaticScroll = false
            }
        }
    }

    static func characterIndex(ofLine line: Int, in text: String) -> Int {
        let nsText = text as NSString
        let length = nsText.length
        if line <= 1 { return 0 }
        
        var currentLine = 1
        var index = 0
        while index < length {
            let ch = nsText.character(at: index)
            if ch == 10 { // \n
                currentLine += 1
                if currentLine == line {
                    return min(index + 1, length)
                }
            }
            index += 1
        }
        return length
    }
}


/// Подкласс NSTextView с подсветкой Markdown и кастомным шрифтом/отступами.
final class MarkdownTextView: NSTextView {
    /// Диапазон строк для подсветки активного логического блока
    var highlightedLineRange: ClosedRange<Int>? = nil {
        didSet {
            if oldValue != highlightedLineRange {
                needsDisplay = true
            }
        }
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let range = highlightedLineRange,
              let layoutManager = layoutManager,
              let textContainer = textContainer,
              let storage = textStorage else { return }

        let string = storage.string as NSString
        let totalLength = string.length
        guard totalLength > 0 else { return }

        let startChar = CodeEditorView.characterIndex(ofLine: range.lowerBound, in: string as String)
        let endLine = range.upperBound
        let endChar: Int
        if endLine >= range.lowerBound {
            let nextLineChar = CodeEditorView.characterIndex(ofLine: endLine + 1, in: string as String)
            endChar = min(totalLength, max(startChar, nextLineChar > startChar ? nextLineChar : totalLength))
        } else {
            endChar = min(totalLength, startChar + 1)
        }

        let charLength = max(1, endChar - startChar)
        let safeLength = min(charLength, totalLength - min(startChar, totalLength))
        let charRange = NSRange(location: min(startChar, totalLength), length: safeLength)
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.location != NSNotFound && glyphRange.length > 0 else { return }

        var blockRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        blockRect.origin.x = 4
        blockRect.size.width = max(10, bounds.width - 8)
        blockRect.origin.y += textContainerInset.height
        blockRect.origin.y -= 2
        blockRect.size.height += 4

        NSGraphicsContext.saveGraphicsState()
        let path = NSBezierPath(roundedRect: blockRect, xRadius: 6, yRadius: 6)
        
        // Полупрозрачный фон акцентного цвета
        NSColor.controlAccentColor.withAlphaComponent(0.08).setFill()
        path.fill()

        // Тонкая полупрозрачная обводка
        NSColor.controlAccentColor.withAlphaComponent(0.35).setStroke()
        path.lineWidth = 1.0
        path.stroke()

        // Акцентная левая полоска
        let leftBarRect = NSRect(x: blockRect.minX, y: blockRect.minY, width: 3.5, height: blockRect.height)
        let leftBarPath = NSBezierPath(roundedRect: leftBarRect, xRadius: 1.75, yRadius: 1.75)
        NSColor.controlAccentColor.withAlphaComponent(0.75).setFill()
        leftBarPath.fill()

        NSGraphicsContext.restoreGraphicsState()
    }

    override var undoManager: UndoManager? {
        return window?.undoManager ?? super.undoManager
    }

    override func scrollWheel(with event: NSEvent) {
        // Блокируем чисто горизонтальный сдвиг и паразитное раскачивание влево-вправо
        if abs(event.scrollingDeltaX) > 0 && abs(event.scrollingDeltaY) < 0.1 {
            return
        }
        super.scrollWheel(with: event)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    private func configure() {
        isEditable = true
        isSelectable = true
        isRichText = true           // нужен для атрибутов (цвета)
        allowsImageEditing = false
        importsGraphics = false
        drawsBackground = true
        backgroundColor = .clear
        insertionPointColor = NSColor.labelColor
        font = NSFont.monospacedSystemFont(ofSize: CGFloat(SettingsStore.shared.editorFontSize), weight: .regular)
        defaultParagraphStyle = {
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 4
            return style
        }()
        textContainerInset = NSSize(width: 18, height: 12)
        textColor = NSColor.labelColor
        isHorizontallyResizable = false
        isVerticallyResizable = true
        autoresizingMask = [.width]
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        smartInsertDeleteEnabled = false
    }

    /// Порог «большого» документа по строкам (Этап 3): выше — подсвечивается
    /// видимый диапазон с запасом вместо полной переразметки на каждый debounce.
    static let visibleHighlightLineThreshold = 2000
    /// Запас подсветки вокруг видимой области (строк вверх/вниз).
    static let visibleHighlightContextLines = 200

    /// Токенизация и подсветка. Простейший, но читаемый Markdown-хайлайтер:
    /// заголовки, жирный/курсив/зачёрк, inline-код, цитаты, ссылки, списки, код-блоки.
    /// Этап 3: для больших документов (>= 2000 строк) размечается только видимый
    /// диапазон (+ запас) — полная переразметка `storage.string` на каждый
    /// debounce доминировала в профиле. Маленькие — как раньше (полностью).
    /// Восстановление selection и НЕподсвеченного (базового) оформления
    /// видимой части сохранены: вне окна ставится базовый стиль, поэтому
    /// вне-экранные атрибуты не «залипают» старыми цветами.
    func highlight() {
        guard let storage = textStorage else { return }
        let savedSelection = selectedRange()

        let fullText = storage.string
        let nsFull = fullText as NSString
        let lineCount = fullText.split(separator: "\n", omittingEmptySubsequences: false).count

        if lineCount < Self.visibleHighlightLineThreshold {
            // Маленький документ: полная переразметка, как раньше.
            let attributed = MarkdownHighlighter.highlight(fullText)
            storage.beginEditing()
            storage.setAttributedString(attributed)
            storage.endEditing()
        } else {
            // Большой документ: окно видимости + запас строк.
            let charRange = visibleCharacterRange(in: storage, fullLength: nsFull.length)
            storage.beginEditing()
            // 1) Сброс в базовый стиль для ВСЕГО документа (вне окна гасим
            //    возможные старые цвета, сохраняя шрифт/цвет темы).
            let fontSize = CGFloat(SettingsStore.shared.editorFontSize)
            let base: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            storage.setAttributes(base, range: NSRange(location: 0, length: nsFull.length))
            // 2) Подсветка только окна (строки вокруг видимой области):
            //    размечаем подстроку тем же хайлайтером и переносим её
            //    атрибуты со смещением окна.
            if charRange.length > 0 {
                let windowText = nsFull.substring(with: charRange)
                let highlighted = MarkdownHighlighter.highlight(windowText)
                highlighted.enumerateAttributes(
                    in: NSRange(location: 0, length: highlighted.length)) { attrs, range, _ in
                        storage.setAttributes(
                            attrs,
                            range: NSRange(location: charRange.location + range.location, length: range.length))
                }
            }
            storage.endEditing()
        }

        // Восстанавливаем курсор ПОСЛЕ замены
        let safeLocation = min(savedSelection.location, storage.length)
        let safeLength = min(savedSelection.length, storage.length - safeLocation)
        setSelectedRange(NSRange(location: safeLocation, length: safeLength))
    }

    /// Этап 3: символьный диапазон видимой области (+ запас строк) в storage.
    private func visibleCharacterRange(in storage: NSTextStorage, fullLength: Int) -> NSRange {
        let layoutManagerGuard = layoutManager
        let containerGuard = textContainer
        guard let layoutManager = layoutManagerGuard, let textContainer = containerGuard else {
            return NSRange(location: 0, length: fullLength)
        }

        var visibleRect = enclosingScrollView?.contentView.bounds ?? bounds
        // Переводим видимую rect в координаты контейнера (без инсет-запаса).
        let inset = textContainerInset.height
        visibleRect.origin.y -= inset

        let startGlyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: max(0, visibleRect.minY)), in: textContainer)
        let endGlyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: max(0, visibleRect.maxY)), in: textContainer)
        let startChar = layoutManager.characterIndexForGlyph(at: min(startGlyph, endGlyph))
        let endChar = layoutManager.characterIndexForGlyph(at: max(startGlyph, endGlyph))

        // Расширяем на запас строк вверх/вниз.
        let context = Self.visibleHighlightContextLines
        let ns = storage.string as NSString
        let startLineRange = ns.lineRange(for: NSRange(location: min(startChar, fullLength - 1), length: 0))
        var windowStart = startLineRange.location
        for _ in 0..<context where windowStart > 0 {
            let prev = ns.lineRange(for: NSRange(location: windowStart - 1, length: 0))
            windowStart = prev.location
        }
        let endLineRange = ns.lineRange(for: NSRange(location: min(max(endChar, startChar), fullLength - 1), length: 0))
        var windowEnd = endLineRange.location + endLineRange.length
        for _ in 0..<context where windowEnd < fullLength {
            let next = ns.lineRange(for: NSRange(location: windowEnd, length: 0))
            windowEnd = next.location + next.length
        }

        let length = max(0, min(windowEnd, fullLength) - windowStart)
        return NSRange(location: windowStart, length: length)
    }
}
