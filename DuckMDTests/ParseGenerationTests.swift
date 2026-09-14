import XCTest
@testable import DuckMD

/// Этап 3 (производительность): монотонное поколение парсинга. Фоновые задачи
/// могут завершаться не по порядку — устаревший generation не должен применять
/// свои blocks/renderedHTML (раньше поздний медленный parse затирал свежий
/// HTML устаревшим). Логика применения вынесена в `applyParseResult` —
/// тестируется без UI/WebView.
final class ParseGenerationTests: XCTestCase {

    func testApplyParseResultWithCurrentGenerationApplies() {
        let doc = MarkdownDocument(text: "# Старт")
        // Актуальное поколение — применяем безусловно.
        doc.applyParseResult(generation: doc.parseGeneration, blocks: [], html: "<p>новый</p>")
        XCTAssertEqual(doc.renderedHTML, "<p>новый</p>")
    }

    func testStaleGenerationIsRejected() {
        let doc = MarkdownDocument(text: "# Старт")
        let fresh = doc.parseGeneration
        // Устаревший (меньше актуального) — отсев: HTML остаётся первичным.
        doc.applyParseResult(generation: fresh - 1, blocks: [], html: "<p>устаревший</p>")
        XCTAssertNotEqual(doc.renderedHTML, "<p>устаревший</p>")
        XCTAssertTrue(doc.renderedHTML.contains("<h1"), "первичный синхронный HTML жив")
    }

    func testFutureGenerationIsRejected() {
        let doc = MarkdownDocument(text: "# Старт")
        doc.applyParseResult(generation: doc.parseGeneration + 5, blocks: [], html: "<p>из будущего</p>")
        XCTAssertNotEqual(doc.renderedHTML, "<p>из будущего</p>")
    }

    func testOutOfOrderBackgroundResultsApplyOnlyLatest() {
        // Сценарий «два parse с разными generation»: медленная старая задача
        // завершается ПОСЛЕ быстрой новой — применяется только новая.
        // Порядок как в scheduleReparse: планирование инкрементирует поколение,
        // затем фоновый результат применяется со своим номером.
        let doc = MarkdownDocument(text: "# Старт")
        let g1 = doc.advanceGeneration() // старая задача ушла в фон
        let g2 = doc.advanceGeneration() // новая задача ушла в фон
        doc.applyParseResult(generation: g2, blocks: [], html: "<p>вторая</p>")
        doc.applyParseResult(generation: g1, blocks: [], html: "<p>первая, медленная</p>")
        XCTAssertEqual(doc.renderedHTML, "<p>вторая</p>",
                       "устаревший результат, пришедший позже, не должен затирать свежий")
    }

    func testRegenerateHTMLIncrementsGeneration() {
        let doc = MarkdownDocument(text: "# Старт")
        let before = doc.parseGeneration
        doc.regenerateHTML(theme: HTMLTheme(cssBody: "body { color: red; }", fontSize: 15))
        XCTAssertGreaterThan(doc.parseGeneration, before,
                             "regenerateHTML обязан инкрементировать поколение (защита от out-of-order)")
    }

    // MARK: - Большие документы: порог и отложенный первичный HTML

    func testIsLargeDocumentByLinesAndBytes() {
        let small = String(repeating: "строка\n", count: 10)
        XCTAssertFalse(MarkdownDocument.isLargeDocument(small))

        let manyLines = String(repeating: "строка\n", count: MarkdownDocument.largeDocumentLineThreshold + 1)
        XCTAssertTrue(MarkdownDocument.isLargeDocument(manyLines), "порог по строкам")

        let bigBytes = String(repeating: "a", count: MarkdownDocument.largeDocumentByteThreshold)
        XCTAssertTrue(MarkdownDocument.isLargeDocument(bigBytes), "порог по байтам")
    }

    /// Этап 3: большой документ — первичный parse в фоне; на экране shell, а не
    /// «белый экран навсегда»: после applyParseResult HTML приходит полностью.
    func testLargeDocumentDelaysPrimaryRenderButAppliesOnGeneration() {
        let manyLines = String(repeating: "# Заголовок пункта\n\nАбзац текста.\n\n",
                               count: MarkdownDocument.largeDocumentLineThreshold / 3 + 1)
        XCTAssertTrue(MarkdownDocument.isLargeDocument(manyLines))
        let doc = MarkdownDocument(text: manyLines)
        // Первичный HTML отложен (shell — не блокируем main на секунды).
        XCTAssertTrue(doc.renderedHTML.isEmpty || !doc.renderedHTML.contains("<h1"),
                      "первичный рендер большого документа не обязан быть синхронным")
        // Фоновая задача завершится → applyParseResult с актуальным поколением.
        let exp = expectation(description: "background primary parse applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exp.fulfill() }
        wait(for: [exp], timeout: 5)
        XCTAssertTrue(doc.renderedHTML.contains("<h1"), "фоновый parse применился, shell заменён контентом")
        XCTAssertFalse(doc.parsedBlocks.isEmpty)
    }

    // MARK: - Маленькие документы: синхронный контракт сохранён (Этап 1/2)

    func testSmallDocumentStillRendersSynchronously() throws {
        // Этап 5 (404): синхронный контракт проверяется на СУЩЕСТВУЮЩЕЙ картинке —
        // отсутствующий файл теперь даёт плейсхолдер, а не <img>.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89]).write(to: dir.appendingPathComponent("pic.png"))

        let doc = MarkdownDocument(text: "![](pic.png)",
                                   documentURL: dir.appendingPathComponent("notes.md"))
        XCTAssertTrue(doc.renderedHTML.contains("src=\"file://"),
                      "синхронный первичный рендер с резолвом картинок — контракт маленьких документов")
        XCTAssertFalse(doc.renderedHTML.contains("файл изображения не найден"),
                       "существующая картинка не должна стать 404-плейсхолдером")
    }
}

/// Этап 3: кэш regex хайлайтера и устойчивость на большом тексте.
final class HighlighterPerformanceTests: XCTestCase {

    func testCachedRegexesAreValid() {
        XCTAssertTrue(MarkdownHighlighter.cachedRegexesAreValid,
                      "все статические regex-паттерны должны компилироваться один раз")
    }

    func testHighlightLargeTextDoesNotCrashAndPreservesLength() {
        let chunk = "# Заголовок\n\nПараграф с **жирным**, *курсивом*, `кодом`, ~~зачёркнутым~~ и [ссылкой](https://example.com).\n\n- пункт 1\n- пункт 2\n\n```swift\nlet x = 1\n```\n\n"
        let large = String(repeating: chunk, count: 2000) // ~220К символов
        let result = MarkdownHighlighter.highlight(large)
        XCTAssertEqual(result.length, (large as NSString).length,
                       "подсветка не должна терять/добавлять символы большого текста")
    }

    func testListMarkerLengthWithCheckbox() {
        let attr = MarkdownHighlighter.highlight("- [x] выполнено")
        XCTAssertEqual(attr.length, (("- [x] выполнено") as NSString).length)
    }
}
