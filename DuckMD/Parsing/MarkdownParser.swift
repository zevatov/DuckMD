import Foundation
import Markdown

/// Парсер строки Markdown → массив `MarkdownBlock`.
/// Оборачивает swift-markdown: AST (cmark-gfm) → типобезопасные блоки.
/// GFM-расширения (таблицы, ~~зачёркивание~~, todo) парсятся по умолчанию;
/// умные кавычки/тире тоже включены «из коробки».
struct MarkdownParser {
    /// Кэшируем синглтон (парсинг — потокобезопасен).
    static let shared = MarkdownParser()

    /// Основной метод: строка → блоки.
    func parse(_ source: String) -> [MarkdownBlock] {
        let document = Document(parsing: source)
        return convertChildren(document)
    }

    // MARK: - Block-level

    private func convertChildren(_ element: any Markup) -> [MarkdownBlock] {
        element.children.compactMap { child -> MarkdownBlock? in
            let startLine = child.range?.start.line
            let endLine = child.range?.end.line
            switch child {
            case let h as Heading:
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .heading(level: h.level, inline: convertInline(h.children)))

            case let p as Paragraph:
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .paragraph(convertInline(p.children)))

            case let bq as BlockQuote:
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .blockquote(convertChildren(bq)))

            case let ul as UnorderedList:
                let items = ul.listItems.map { li -> [MarkdownBlock] in
                    var blocks = convertChildren(li)
                    let liLine = li.range?.start.line
                    if blocks.isEmpty, let line = liLine {
                        blocks = [MarkdownBlock(sourceLine: line, endLine: li.range?.end.line, content: .paragraph([]))]
                    } else if let line = liLine, !blocks.isEmpty && blocks[0].sourceLine == nil {
                        blocks[0] = MarkdownBlock(sourceLine: line, endLine: blocks[0].endLine, content: blocks[0].content)
                    }
                    return Self.taskItemBlocks(blocks, checkbox: li.checkbox)
                }
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .bulletList(items: Array(items)))

            case let ol as OrderedList:
                let items = ol.listItems.map { li -> [MarkdownBlock] in
                    var blocks = convertChildren(li)
                    let liLine = li.range?.start.line
                    if blocks.isEmpty, let line = liLine {
                        blocks = [MarkdownBlock(sourceLine: line, endLine: li.range?.end.line, content: .paragraph([]))]
                    } else if let line = liLine, !blocks.isEmpty && blocks[0].sourceLine == nil {
                        blocks[0] = MarkdownBlock(sourceLine: line, endLine: blocks[0].endLine, content: blocks[0].content)
                    }
                    return Self.taskItemBlocks(blocks, checkbox: li.checkbox)
                }
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .orderedList(items: Array(items), start: Int(ol.startIndex)))

            case let cb as CodeBlock:
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .code(language: cb.language, content: cb.code))

            case is ThematicBreak:
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .thematicBreak)

            case let t as Table:
                return convertTable(t)

            case let html as HTMLBlock:
                return MarkdownBlock(sourceLine: startLine, endLine: endLine, content: .html(content: html.rawHTML))

            default:
                return nil
            }
        }
    }

    private func convertTable(_ table: Table) -> MarkdownBlock {
        // header: [[MarkdownInline]] — массив ячеек, каждая ячейка = массив инлайнов
        let headerCells: [[MarkdownInline]] = Array(
            table.head.cells.map { convertInline($0.children) }
        )
        // rows: [[[MarkdownInline]]] — массив строк; строка = массив ячеек; ячейка = массив инлайнов
        let bodyRows: [[[MarkdownInline]]] = Array(
            table.body.rows.map { row in
                Array(row.cells.map { convertInline($0.children) })
            }
        )
        let alignments: [TableColumnAlignment] = Array(
            table.columnAlignments.map { alignment -> TableColumnAlignment in
                switch alignment {
                case .left: return .left
                case .center: return .center
                case .right: return .right
                default: return .none
                }
            }
        )
        return MarkdownBlock(sourceLine: table.range?.start.line, endLine: table.range?.end.line, content: .table(header: headerCells, rows: bodyRows, alignments: alignments))
    }

    // MARK: - Inline-level

    private func convertInline(_ children: any Sequence<Markup>) -> [MarkdownInline] {
        children.flatMap { child -> [MarkdownInline] in
            switch child {
            case let t as Text:
                return [.text(t.string)]

            case let s as Strong:
                return [.strong(convertInline(s.children))]

            case let e as Emphasis:
                return [.emphasis(convertInline(e.children))]

            case let c as InlineCode:
                return [.code(c.code)]

            case let l as Link:
                return [.link(text: convertInline(l.children),
                              url: l.destination,
                              title: l.title)]

            case let img as Image:
                return [.image(alt: img.children.compactMap { $0 as? Text }.map(\.string).joined(),
                               url: img.source,
                               title: img.title)]

            case let st as Strikethrough:
                return [.strikethrough(convertInline(st.children))]

            case is SoftBreak:
                return [.softBreak]

            case is LineBreak:
                return [.lineBreak]

            default:
                if let t = child as? Text {
                    return [.text(t.string)]
                }
                return []
            }
        }
    }
    // MARK: - Task list (SPEC R-MD-4)

    /// GFM task list: чекбокс — атрибут `ListItem.checkbox` в swift-markdown
    /// (cmark-gfm extension «tasklist»; сам cmark убирает текст «[ ] » из контента).
    /// nil-checkbox → пункт без изменений; с чекбоксом → `.checkbox` первым inline
    /// в первом параграфе пункта, чтобы рендер дал ☐/☑.
    private static func taskItemBlocks(_ blocks: [MarkdownBlock], checkbox: Checkbox?) -> [MarkdownBlock] {
        guard let checkbox else { return blocks }
        let isChecked = (checkbox == .checked)
        guard case .paragraph(let inlines)? = blocks.first?.content else {
            // Пункт без параграфа (пустой «- [ ]»): добавляем чекбокс отдельным параграфом.
            var updated = blocks
            let item = MarkdownBlock(sourceLine: nil, endLine: nil, content: .paragraph([.checkbox(isChecked: isChecked)]))
            updated.insert(item, at: 0)
            return updated
        }
        var updated = blocks
        updated[0] = MarkdownBlock(
            sourceLine: blocks[0].sourceLine,
            endLine: blocks[0].endLine,
            content: .paragraph([.checkbox(isChecked: isChecked)] + inlines)
        )
        return updated
    }
}

// MARK: - ListItem helpers

private extension ListItemContainer {
    /// Дочерние элементы списка как `ListItem`.
    var listItems: [ListItem] { children.compactMap { $0 as? ListItem } }
}
