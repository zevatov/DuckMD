import SwiftUI

// MARK: - WebPreviewView Factory (R4)

extension WebPreviewView {
    /// Фабрика стандартного превью для режимов редактирования (R4, дедупликация).
    /// Табличные операции (add/del row/col) идентичны во всех местах вызова —
    /// собираются здесь; текстовые колбэки редактирования передаются наружу,
    /// т.к. различаются валидацией (ContentView валидирует payload, Split — нет).
    /// Поведение вызывающих сторон не меняется — только дедуп.
    static func makeStandard(
        document: MarkdownDocument,
        hideScrollbar: Bool = false,
        scrollFraction: CGFloat? = nil,
        scrollPosition: (line: Int, offset: CGFloat, fraction: CGFloat)? = nil,
        activeLine: Int = 1,
        activeCol: Int? = nil,
        onScroll: ((CGFloat) -> Void)? = nil,
        onScrollPosition: ((Int, Int?, CGFloat, CGFloat) -> Void)? = nil,
        onElementClicked: ((Int) -> Void)? = nil,
        onElementEdited: @escaping (Int, String) -> Void,
        onTableCellEdited: @escaping (Int, Int, Int, String) -> Void,
        onCheckboxToggled: ((Int, Bool) -> Void)? = nil,
        updateText: @escaping (String) -> Void
    ) -> WebPreviewView {
        WebPreviewView(
            htmlContent: document.renderedHTML,
            documentFileURL: document.documentURL,
            scrollFraction: scrollFraction,
            scrollPosition: scrollPosition,
            activeLine: activeLine,
            activeCol: activeCol,
            onScroll: onScroll,
            onScrollPosition: onScrollPosition,
            onElementClicked: onElementClicked,
            onElementEdited: onElementEdited,
            onTableCellEdited: onTableCellEdited,
            onTableAddRow: { line in
                updateText(RenderEditParser.addRow(tableLine: line, to: document.text))
            },
            onTableAddCol: { line in
                updateText(RenderEditParser.addColumn(tableLine: line, to: document.text))
            },
            onTableDelRow: { line, row in
                updateText(RenderEditParser.deleteRow(tableLine: line, row: row, to: document.text))
            },
            onTableDelCol: { line, col in
                updateText(RenderEditParser.deleteColumn(tableLine: line, col: col, to: document.text))
            },
            onCheckboxToggled: onCheckboxToggled,
            hideScrollbar: hideScrollbar
        )
    }
}
