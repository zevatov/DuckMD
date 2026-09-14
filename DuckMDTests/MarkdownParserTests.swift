import XCTest
@testable import DuckMD

/// R10: тесты MarkdownParser на чистых функциях (AST → MarkdownBlock).
/// Без UI/WKWebView — только парсинг и sourceLine-корректность.
final class MarkdownParserTests: XCTestCase {

    // MARK: - Заголовки

    func testHeadingLevelAndText() {
        let blocks = MarkdownParser().parse("# Заголовок")
        XCTAssertEqual(blocks.count, 1)
        guard case .heading(let level, let inline) = blocks[0].content else {
            return XCTFail("Ожидался heading, получено: \(blocks[0].content)")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(inline, [.text("Заголовок")])
    }

    func testHeadingLevelThree() {
        let blocks = MarkdownParser().parse("### Мелкий заголовок")
        guard case .heading(let level, let inline) = blocks[0].content else {
            return XCTFail("Ожидался heading")
        }
        XCTAssertEqual(level, 3)
        XCTAssertEqual(inline, [.text("Мелкий заголовок")])
    }

    // MARK: - Списки

    func testBulletListItems() {
        let blocks = MarkdownParser().parse("- первый\n- второй")
        XCTAssertEqual(blocks.count, 1)
        guard case .bulletList(let items) = blocks[0].content else {
            return XCTFail("Ожидался bulletList, получено: \(blocks[0].content)")
        }
        XCTAssertEqual(items.count, 2)
    }

    func testOrderedListItems() {
        let blocks = MarkdownParser().parse("1. один\n2. два")
        XCTAssertEqual(blocks.count, 1)
        guard case .orderedList(let items, _) = blocks[0].content else {
            return XCTFail("Ожидался orderedList, получено: \(blocks[0].content)")
        }
        XCTAssertEqual(items.count, 2)
    }

    // MARK: - Task list чекбоксы (SPEC R-MD-4)

    func testTaskListCheckboxUncheckedAndChecked() {
        let blocks = MarkdownParser().parse("- [ ] купить хлеб\n- [x] молоко")
        XCTAssertEqual(blocks.count, 1)
        guard case .bulletList(let items) = blocks[0].content else {
            return XCTFail("Ожидался bulletList, получено: \(blocks[0].content)")
        }
        XCTAssertEqual(items.count, 2)
        for (idx, item) in items.enumerated() {
            guard case .paragraph(let inlines)? = item.first?.content,
                  case .checkbox(let isChecked)? = inlines.first else {
                return XCTFail("Пункт \(idx): ожидался paragraph с ведущим checkbox, получено: \(String(describing: item.first?.content))")
            }
            XCTAssertEqual(isChecked, idx == 1, "Первый пункт unchecked, второй — checked")
            // Текст после чекбокса: cmark убирает сам маркер «[x] », контент сохраняется.
            let texts = inlines.compactMap { inline -> String? in
                if case .text(let s) = inline { return s }
                return nil
            }
            XCTAssertTrue(texts.joined().contains(idx == 0 ? "хлеб" : "молоко"), "Текст пункта должен сохраниться: \(inlines)")
        }
    }

    func testTaskCheckboxXUpperCaseIsChecked() {
        // GFM: чекбокс регистронезависим — [X] тоже checked.
        let blocks = MarkdownParser().parse("- [X] завершено")
        guard case .bulletList(let items) = blocks[0].content,
              case .paragraph(let inlines)? = items[0].first?.content,
              case .checkbox(let isChecked)? = inlines.first else {
            return XCTFail("Ожидался bulletList с ведущим checkbox")
        }
        XCTAssertTrue(isChecked, "[X] в верхнем регистре тоже checked")
    }

    func testRegularListHasNoCheckbox() {
        let blocks = MarkdownParser().parse("- обычный пункт")
        guard case .bulletList(let items) = blocks[0].content,
              case .paragraph(let inlines)? = items[0].first?.content,
              case .text(let text)? = inlines.first else {
            return XCTFail("Ожидался bulletList с текстовым paragraph")
        }
        XCTAssertEqual(text, "обычный пункт", "Обычный список без чекбокса — первый inline остаётся текстом")
    }

    // MARK: - Таблицы

    func testTableStructure() {
        let blocks = MarkdownParser().parse("| A | B |\n|---|---|\n| 1 | 2 |")
        XCTAssertEqual(blocks.count, 1)
        guard case .table(let header, let rows, _) = blocks[0].content else {
            return XCTFail("Ожидалась таблица, получено: \(blocks[0].content)")
        }
        XCTAssertEqual(header.count, 2)
        XCTAssertEqual(header[0], [.text("A")])
        XCTAssertEqual(header[1], [.text("B")])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0], [[.text("1")], [.text("2")]])
    }

    // MARK: - Code

    func testFencedCodeBlockWithLanguage() {
        let blocks = MarkdownParser().parse("```swift\nlet x = 1\n```")
        XCTAssertEqual(blocks.count, 1)
        guard case .code(let language, let content) = blocks[0].content else {
            return XCTFail("Ожидался code-блок, получено: \(blocks[0].content)")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(content.hasPrefix("let x = 1"))
    }

    // MARK: - Raw HTML

    func testRawHTMLBlock() {
        let blocks = MarkdownParser().parse("<div>привет</div>")
        XCTAssertEqual(blocks.count, 1)
        guard case .html(let raw) = blocks[0].content else {
            return XCTFail("Ожидался html-блок, получено: \(blocks[0].content)")
        }
        XCTAssertTrue(raw.contains("<div>привет</div>"))
    }

    // MARK: - Прочее

    func testThematicBreak() {
        let blocks = MarkdownParser().parse("---")
        guard case .thematicBreak = blocks[0].content else {
            return XCTFail("Ожидался thematicBreak, получено: \(blocks[0].content)")
        }
    }

    func testEmptyInputYieldsNoBlocks() {
        XCTAssertTrue(MarkdownParser().parse("").isEmpty)
        XCTAssertTrue(MarkdownParser().parse("   \n  ").isEmpty)
    }

    // MARK: - sourceLine

    func testSourceLinesAreOneBasedAndCorrect() {
        // Строки: 1 — заголовок, 2 — пустая, 3 — абзац.
        let blocks = MarkdownParser().parse("# H1\n\nАбзац")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].sourceLine, 1)
        XCTAssertEqual(blocks[0].endLine, 1)
        XCTAssertEqual(blocks[1].sourceLine, 3)
    }

    func testMultilineBlockSpansSourceLines() {
        let blocks = MarkdownParser().parse("Абзац\nв две строки")
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].sourceLine, 1)
        XCTAssertEqual(blocks[0].endLine, 2)
    }
}
