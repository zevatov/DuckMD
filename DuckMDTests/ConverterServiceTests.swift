import XCTest
@testable import DuckMD

/// R10: лёгкие кейсы ConverterService (txt → markdown, неподдерживаемый формат).
/// Тяжёлые форматы (PDF/DOCX) намеренно не рендерим — только чистая дисковая логика.
final class ConverterServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testTxtConvertsToMarkdownVerbatim() throws {
        let url = tempDir.appendingPathComponent("note.txt")
        try "Привет, мир".write(to: url, atomically: true, encoding: .utf8)
        let result = try ConverterService.convert(url: url)
        XCTAssertEqual(result, "Привет, мир")
    }

    func testEmptyTxtConvertsToEmptyMarkdown() throws {
        let url = tempDir.appendingPathComponent("empty.txt")
        try "".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try ConverterService.convert(url: url), "")
    }

    func testUnsupportedFormatThrows() throws {
        let url = tempDir.appendingPathComponent("archive.xyz")
        try "данные".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ConverterService.convert(url: url)) { error in
            guard case ConversionError.unsupportedFormat = error else {
                return XCTFail("Ожидался ConversionError.unsupportedFormat, получено: \(error)")
            }
        }
    }

    func testConversionErrorMessagesLocalized() {
        XCTAssertFalse(ConversionError.unsupportedFormat.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(ConversionError.invalidPDF.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(ConversionError.loadFailed.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(ConversionError.fileTooLarge(bytes: 1).errorDescription?.isEmpty ?? true)
        XCTAssertFalse(ConversionError.tooManyPages(count: 1).errorDescription?.isEmpty ?? true)
        XCTAssertFalse(ConversionError.emptyFile.errorDescription?.isEmpty ?? true)
    }

    // MARK: - Этап 2: лимиты и pre-check

    func testOversizedFileThrowsBeforeParsing() throws {
        let url = tempDir.appendingPathComponent("huge.txt")
        // Размер проверяется до парсинга: пишем sparse-подобный файл через Data(count:)
        // 51 МБ > 50 МБ лимита. Записываем реальный файл (на APFS быстро).
        try Data(count: ConverterService.maxInputFileSize + 1024).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ConverterService.convert(url: url)) { error in
            guard case ConversionError.fileTooLarge = error else {
                return XCTFail("Ожидался ConversionError.fileTooLarge, получено: \(error)")
            }
        }
    }

    func testEmptyNonTxtFileThrows() throws {
        let url = tempDir.appendingPathComponent("empty.pdf")
        try Data().write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try ConverterService.convert(url: url)) { error in
            guard case ConversionError.emptyFile = error else {
                return XCTFail("Ожидался ConversionError.emptyFile, получено: \(error)")
            }
        }
    }

    func testDirectoryInputRejected() throws {
        let dirURL = tempDir.appendingPathComponent("subdir", isDirectory: true)
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dirURL) }
        XCTAssertThrowsError(try ConverterService.convert(url: dirURL)) { error in
            guard case ConversionError.loadFailed = error else {
                return XCTFail("Ожидался ConversionError.loadFailed для директории, получено: \(error)")
            }
        }
    }

    func testLimitsConstants() {
        // Защита от случайного изменения порогов в сторону ослабления.
        XCTAssertEqual(ConverterService.maxInputFileSize, 50 * 1024 * 1024)
        XCTAssertEqual(ConverterService.maxPDFPages, 200)
    }
}
