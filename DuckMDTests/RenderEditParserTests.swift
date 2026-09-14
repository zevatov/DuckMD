import XCTest
@testable import DuckMD

/// R10: тесты RenderEditParser — применённые правки строк, табличные мутации,
/// невалидные line/row/col → правка игнорируется (текст возвращается как есть).
final class RenderEditParserTests: XCTestCase {

    // MARK: - Правки строк

    func testApplyParagraphEdit() {
        let result = RenderEditParser.applyEdit(startLine: 2, endLine: 2, newText: "ВТОРАЯ", to: "первая\nвторая\nтретья")
        XCTAssertEqual(result, "первая\nВТОРАЯ\nтретья")
    }

    func testApplyEditPreservesHeadingPrefix() {
        let result = RenderEditParser.applyEdit(startLine: 1, endLine: 1, newText: "Новый заголовок", to: "# Старый\n\nТело")
        XCTAssertEqual(result, "# Новый заголовок\n\nТело")
    }

    func testApplyEditListPrefixStaysOnFirstLine() {
        let result = RenderEditParser.applyEdit(startLine: 1, endLine: 1, newText: "новый пункт", to: "- старый\n- другой")
        XCTAssertEqual(result, "- новый пункт\n- другой")
    }

    func testApplyEditMultilineReplacement() {
        let result = RenderEditParser.applyEdit(startLine: 1, endLine: 2, newText: "сроки один\nсроки два", to: "раз\nдва\nтри")
        XCTAssertEqual(result, "сроки один\nсроки два\nтри")
    }

    func testApplyEditInvalidLineIgnored() {
        let src = "а\nб"
        XCTAssertEqual(RenderEditParser.applyEdit(startLine: 0, endLine: 0, newText: "x", to: src), src, "line < 1 должен игнорироваться")
        XCTAssertEqual(RenderEditParser.applyEdit(startLine: 99, endLine: 99, newText: "x", to: src), src, "line за пределами документа должен игнорироваться")
    }

    // MARK: - Табличные мутации

    private let table = "| A | B |\n|---|---|\n| 1 | 2 |"

    func testTableCellEditInBody() {
        let result = RenderEditParser.applyTableCellEdit(tableLine: 1, row: 1, col: 0, newText: "X", to: table)
        XCTAssertEqual(result, "| A | B |\n|---|---|\n| X | 2 |")
    }

    func testTableCellEditInHeader() {
        let result = RenderEditParser.applyTableCellEdit(tableLine: 1, row: 0, col: 1, newText: "Y", to: table)
        XCTAssertEqual(result, "| A | Y |\n|---|---|\n| 1 | 2 |")
    }

    func testTableCellEditOutOfRangeIgnored() {
        XCTAssertEqual(RenderEditParser.applyTableCellEdit(tableLine: 1, row: 5, col: 0, newText: "X", to: table), table)
        XCTAssertEqual(RenderEditParser.applyTableCellEdit(tableLine: 1, row: 1, col: 9, newText: "X", to: table), table)
    }

    func testAddRowAppendsEmptyRow() {
        let result = RenderEditParser.addRow(tableLine: 1, to: table)
        XCTAssertEqual(result, "| A | B |\n|---|---|\n| 1 | 2 |\n|  |  |")
    }

    func testDeleteRowRemovesBodyRow() {
        let result = RenderEditParser.deleteRow(tableLine: 1, row: 1, to: table)
        XCTAssertEqual(result, "| A | B |\n|---|---|")
    }

    func testDeleteRowOutOfRangeIgnored() {
        XCTAssertEqual(RenderEditParser.deleteRow(tableLine: 1, row: 9, to: table), table)
    }

    // MARK: - Task Checkbox Toggle (SPEC R-MD-4)

    func testCheckboxToggleUncheckedToChecked() {
        let src = "- [ ] молоко\n- [ ] хлеб"
        let result = RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 1, checked: true)
        XCTAssertEqual(result, ["- [x] молоко", "- [ ] хлеб"])
    }

    func testCheckboxToggleCheckedToUnchecked() {
        let src = "- [x] молоко\n- [ ] хлеб"
        let result = RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 1, checked: false)
        XCTAssertEqual(result, ["- [ ] молоко", "- [ ] хлеб"])
    }

    func testCheckboxTogglePreservesUppercaseX() {
        let src = "* [X] верхний регистр"
        let result = RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 1, checked: true)
        XCTAssertEqual(result, ["* [X] верхний регистр"], "уже checked → без изменений, X сохраняется")
    }

    func testCheckboxToggleInvalidLineReturnsNil() {
        let src = "- [ ] пункт"
        XCTAssertNil(RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 0, checked: true))
        XCTAssertNil(RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 99, checked: true))
        // line указывает не на task-строку → nil
        XCTAssertNil(RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 2, checked: true))
    }

    func testCheckboxToggleNonCheckboxLineReturnsNil() {
        let src = "- обычный пункт\nтекст"
        XCTAssertNil(RenderEditParser.applyCheckboxToggle(lines: src.components(separatedBy: "\n"), line: 1, checked: true))
    }
}
