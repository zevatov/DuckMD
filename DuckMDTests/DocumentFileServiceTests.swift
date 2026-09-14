import XCTest
@testable import DuckMD

/// Этап 1: явные ошибки вместо молчаливых fallback.
/// - Невалидный UTF-8 при открытии — ошибка `DocumentFileError.invalidUTF8`,
///   а не пустая строка (защита от затирания оригинала пустым автосейвом).
/// - Запись пробрасывает ошибки (`writeFailed`), без подавления.
/// - Rename валидируется (запрет слеша/ухода наверх).
/// - Токен собственных записей подавляет эхо вотчера.
final class DocumentFileServiceTests: XCTestCase {

    private var service: DocumentFileService!
    private var tempDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = DocumentFileService()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        service = nil
        try super.tearDownWithError()
    }

    private func makeFile(name: String, data: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    func testReadDocumentTextReturnsFileContent() throws {
        let url = try makeFile(name: "valid.md", data: Data("# Привет\n\nТекст".utf8))
        let text = try service.readDocumentText(at: url)
        XCTAssertEqual(text, "# Привет\n\nТекст")
    }

    func testReadDocumentTextThrowsForMissingFile() {
        let missing = tempDirectory.appendingPathComponent("нет-такого-файла.md")
        XCTAssertThrowsError(try service.readDocumentText(at: missing)) { error in
            XCTAssertTrue(error is CocoaError, "Ожидается ошибка Cocoa (FileManager/Data), получили: \(error)")
        }
    }

    /// Этап 1: невалидный UTF-8 — явная ошибка открытия, а не пустая строка.
    /// Пустая строка позволяла пустому автосейву затeреть оригинал.
    func testReadDocumentTextInvalidUTF8Throws() throws {
        let url = try makeFile(name: "binary.md", data: Data([0xFF, 0xFE, 0x00, 0xC3]))
        XCTAssertThrowsError(try service.readDocumentText(at: url)) { error in
            guard case DocumentFileError.invalidUTF8 = error else {
                XCTFail("Ожидается DocumentFileError.invalidUTF8, получили: \(error)")
                return
            }
        }
    }

    func testReadDocumentTextEmptyFileYieldsEmptyString() throws {
        let url = try makeFile(name: "empty.md", data: Data())
        XCTAssertEqual(try service.readDocumentText(at: url), "")
    }

    /// Оба ридера кидают на невалидном UTF-8 (контракты выровнены):
    /// `readText` (String(contentsOf:)) и `readDocumentText` (invalidUTF8).
    func testReadTextAndReadDocumentTextBothThrowForInvalidUTF8() throws {
        let url = try makeFile(name: "contract.md", data: Data([0xFF, 0xFE, 0x00]))
        XCTAssertThrowsError(try service.readText(at: url))
        XCTAssertThrowsError(try service.readDocumentText(at: url)) { error in
            guard case DocumentFileError.invalidUTF8 = error else {
                XCTFail("Ожидается invalidUTF8, получили: \(error)")
                return
            }
        }
    }

    // MARK: - Этап 1: запись пробрасывает ошибки

    func testWriteTextRoundtripAndSuppressesOwnEvent() throws {
        let url = tempDirectory.appendingPathComponent("write.md")
        service.ownWriteSuppressionWindow = 5.0
        XCTAssertFalse(service.shouldSuppressOwnEvent(), "До записи подавления нет")
        try service.writeText("# hello", to: url)
        XCTAssertTrue(service.shouldSuppressOwnEvent(), "Сразу после своей записи эхо подавляется токеном")
        XCTAssertEqual(try service.readDocumentText(at: url), "# hello")
    }

    func testWriteTextThrowsForMissingDirectory() {
        let bad = tempDirectory.appendingPathComponent("нет-папки").appendingPathComponent("f.md")
        XCTAssertThrowsError(try service.writeText("x", to: bad)) { error in
            guard case DocumentFileError.writeFailed = error else {
                XCTFail("Ожидается writeFailed, получили: \(error)")
                return
            }
        }
    }

    func testOwnEventSuppressionExpires() throws {
        service.ownWriteSuppressionWindow = 0.05
        let url = tempDirectory.appendingPathComponent("sup.md")
        try service.writeText("a", to: url)
        XCTAssertTrue(service.shouldSuppressOwnEvent())
        let exp = expectation(description: "suppression expires")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertFalse(service.shouldSuppressOwnEvent(), "Окно подавления истекло — чужое событие не подавляется")
    }

    // MARK: - Этап 1: валидация rename

    func testValidatedRenameAcceptsNormalAndTrims() throws {
        XCTAssertEqual(try DocumentFileService.validatedRename("  Заметка  "), "Заметка")
        XCTAssertEqual(try DocumentFileService.validatedRename("a b"), "a b")
    }

    func testValidatedRenameRejectsSlashBackslashDotDotEmptyNUL() {
        for bad in ["a/b", "a\\b", "..", ".", "a..b", "", "   ", "a\u{0}b", "../x"] {
            XCTAssertThrowsError(try DocumentFileService.validatedRename(bad), "Имя «\(bad)» обязано отклоняться") { error in
                guard case DocumentFileError.invalidFileName = error else {
                    XCTFail("Ожидается invalidFileName для «\(bad)», получили: \(error)")
                    return
                }
            }
        }
    }

    func testRenameNoOpForSamePath() throws {
        let url = try makeFile(name: "same.md", data: Data("x".utf8))
        let same = try service.rename(from: url, to: "same")
        XCTAssertEqual(same.path, url.path)
    }

    func testRenameRejectsInvalidWithoutTouchingFS() throws {
        let url = try makeFile(name: "orig.md", data: Data("x".utf8))
        XCTAssertThrowsError(try service.rename(from: url, to: "a/b"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "Файл не тронут при невалидном имени")
    }

    // MARK: - Этап 1: suspend блокирует автосейв

    func testIsWriteSuspendedDefaultsFalse() {
        XCTAssertFalse(service.isWriteSuspended)
    }
}
