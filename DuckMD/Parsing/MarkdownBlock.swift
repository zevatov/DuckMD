import Foundation
import Markdown

/// Типобезопасное блочное представление документа, получаемое из AST swift-markdown.
/// Рендер зависит только от этих блоков — не от AST напрямую. Так проще темизировать
/// и позже добавлять WYSIWYG: блоки уже «чистые» и не зависят от внутренней либы.
struct MarkdownBlock: Equatable {
    let sourceLine: Int?
    let endLine: Int?
    let content: Content

    indirect enum Content: Equatable {
        case heading(level: Int, inline: [MarkdownInline])
        case paragraph([MarkdownInline])
        case blockquote([MarkdownBlock])
        case bulletList(items: [[MarkdownBlock]])
        case orderedList(items: [[MarkdownBlock]], start: Int)
        case code(language: String?, content: String)
        case thematicBreak
        case table(header: [[MarkdownInline]], rows: [[[MarkdownInline]]], alignments: [TableColumnAlignment])
        case html(content: String)
    }
}

enum MarkdownInline: Equatable {
    case text(String)
    /// GFM task list чекбокс (SPEC R-MD-4): `- [ ] `/`- [x] ` в пункте списка.
    /// В preview — интерактивный input (toggle через checkboxToggleHandler),
    /// в export — статичный span ☐/☑.
    case checkbox(isChecked: Bool)
    case strong([MarkdownInline])
    case emphasis([MarkdownInline])
    case code(String)
    case link(text: [MarkdownInline], url: String?, title: String?)
    case image(alt: String, url: String?, title: String?)
    case softBreak
    case lineBreak
    case strikethrough([MarkdownInline])
}

enum TableColumnAlignment: Equatable {
    case none, left, center, right
}
