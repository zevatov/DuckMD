import AppKit

// MARK: - Line Number Ruler View

/// Гаттер с номерами строк для NSTextView.
/// Вынесен из CodeEditorView.swift (R8).
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView ?? NSScrollView(), orientation: .verticalRuler)
        self.ruleThickness = 36
        self.clientView = textView
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Вычисляет точную нижнюю границу шапки окна и светофоров в системе координат линейки
    private var topBarInset: CGFloat {
        if let window = self.window {
            // 1. Точная позиция контейнера светофоров в координатах линейки
            if let closeBtn = window.standardWindowButton(.closeButton),
               let btnSuperview = closeBtn.superview {
                let rectInRuler = self.convert(btnSuperview.bounds, from: btnSuperview)
                let bottom = rectInRuler.maxY + 12
                if bottom > 20 { return max(bottom, 54) }
            }
            // 2. Fallback через разницу contentLayoutRect
            let titlebarH = window.frame.height - window.contentLayoutRect.height
            if titlebarH > 0 { return titlebarH }
        }
        return max(self.safeAreaInsets.top, scrollView?.contentInsets.top ?? 0, 56)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let currentTopInset = topBarInset

        // Очищаем область под светофорами от любых артефактов
        let topClearRect = NSRect(x: 0, y: 0, width: bounds.width, height: currentTopInset)
        if rect.intersects(topClearRect) {
            NSGraphicsContext.current?.cgContext.clear(rect.intersection(topClearRect))
        }

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let fontSize = max(CGFloat(SettingsStore.shared.editorFontSize) - 2, 9)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let text = textView.string
        let lineCount = max(1, text.components(separatedBy: "\n").count)
        let sampleNumber = String(repeating: "8", count: max("\(lineCount)".count, 2)) as NSString
        let sampleSize = sampleNumber.size(withAttributes: attrs)
        let neededThickness = max(36, ceil(sampleSize.width + 16))
        if abs(ruleThickness - neededThickness) > 0.5 {
            ruleThickness = neededThickness
        }

        // Отрисовка тонкого Apple-style разделителя справа (строго ниже светофоров)
        let startY = max(rect.minY, currentTopInset)
        if startY < rect.maxY {
            let separatorX = bounds.width - 0.5
            let separatorPath = NSBezierPath()
            separatorPath.move(to: NSPoint(x: separatorX, y: startY))
            separatorPath.line(to: NSPoint(x: separatorX, y: rect.maxY))
            separatorPath.lineWidth = 1.0
            NSColor.separatorColor.withAlphaComponent(0.18).setStroke()
            separatorPath.stroke()
        }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
        let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Подсчитаем физические строки до начала видимого диапазона
        var lineNumber = 1
        let textNSString = text as NSString
        let prefix = textNSString.substring(to: characterRange.location)
        for codeUnit in prefix.utf16 {
            if codeUnit == 10 { // '\n'
                lineNumber += 1
            }
        }

        let inset = textView.textContainerInset.height

        // Будем перечислять фрагменты строк в layoutManager
        var charIndex = characterRange.location
        let endCharIndex = NSMaxRange(characterRange)

        while charIndex < endCharIndex {
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: charIndex)
            var effectiveGlyphRange = NSRange(location: NSNotFound, length: 0)
            let lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &effectiveGlyphRange)
            let lineCharRange = layoutManager.characterRange(forGlyphRange: effectiveGlyphRange, actualGlyphRange: nil)

            // Если этот фрагмент является началом физической строки (charIndex == 0 или символ перед ним '\n')
            let isPhysicalLineStart = lineCharRange.location == 0 ||
                textNSString.character(at: lineCharRange.location - 1) == 10 // '\n'

            if isPhysicalLineStart {
                let drawY = lineRect.origin.y + inset - visibleRect.origin.y
                // Рисуем номера строк строго ниже зоны шапки и светофоров
                if drawY >= currentTopInset {
                    let label = "\(lineNumber)" as NSString
                    let labelSize = label.size(withAttributes: attrs)
                    let x = ruleThickness - labelSize.width - 8
                    let y = drawY + (lineRect.height - labelSize.height) / 2
                    label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
                }

                lineNumber += 1
            }

            charIndex = NSMaxRange(lineCharRange)
            if charIndex <= lineCharRange.location { break } // Защита от зависания
        }

        // Если текст пустой или заканчивается на перевод строки, отрисовываем пустую строку в самом конце
        if text.isEmpty {
            let extraRect = layoutManager.extraLineFragmentRect
            let drawY = extraRect.origin.y + inset - visibleRect.origin.y
            if drawY >= currentTopInset {
                let label = "1" as NSString
                let labelSize = label.size(withAttributes: attrs)
                let x = ruleThickness - labelSize.width - 8
                let y = drawY + (extraRect.height - labelSize.height) / 2
                label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
        } else if text.hasSuffix("\n") && charIndex >= text.utf16.count {
            let extraRect = layoutManager.extraLineFragmentRect
            let drawY = extraRect.origin.y + inset - visibleRect.origin.y
            if drawY >= currentTopInset {
                let label = "\(lineNumber)" as NSString
                let labelSize = label.size(withAttributes: attrs)
                let x = ruleThickness - labelSize.width - 8
                let y = drawY + (extraRect.height - labelSize.height) / 2
                label.draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
            }
        }
    }
}
