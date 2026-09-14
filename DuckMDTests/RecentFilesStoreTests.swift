import XCTest
@testable import DuckMD

/// R10: чистая логика лимита RecentFilesStore (R10-refactor: applyingLimit).
/// Путь персиста (Application Support) не инъектируется, поэтому JSON-персист
/// в temp здесь не тестируется — проверяется только чистая логика лимита,
/// без касания синглтона RecentFilesStore.shared.
final class RecentFilesStoreTests: XCTestCase {

    private func makeFile(name: String, opened: Date = Date()) -> RecentFile {
        RecentFile(
            url: URL(fileURLWithPath: "/tmp/DuckMDTests/\(name).md"),
            bookmarkData: nil,
            lastOpened: opened,
            lastModified: opened,
            title: name,
            preview: "",
            wordCount: 0,
            fileSize: 0
        )
    }

    func testLimitTrimsListKeepingNewestFirst() {
        let files = (0..<5).map { makeFile(name: "f\($0)") }
        let limited = RecentFilesStore.applyingLimit(files, limit: 3)
        XCTAssertEqual(limited.count, 3)
        // Порядок сохраняется: список отсортирован «новые в начале».
        XCTAssertEqual(limited.map(\.title), ["f0", "f1", "f2"])
    }

    func testLimitZeroStillKeepsOneEntry() {
        let files = (0..<3).map { makeFile(name: "f\($0)") }
        let limited = RecentFilesStore.applyingLimit(files, limit: 0)
        XCTAssertEqual(limited.count, 1, "max(limit, 1): нулевой лимит не должен опустошать список")
        XCTAssertEqual(limited.first?.title, "f0")
    }

    func testLimitAboveCountIsNoOp() {
        let files = (0..<3).map { makeFile(name: "f\($0)") }
        let limited = RecentFilesStore.applyingLimit(files, limit: 50)
        XCTAssertEqual(limited.count, 3)
        XCTAssertEqual(limited.map(\.title), ["f0", "f1", "f2"])
        XCTAssertEqual(limited.map(\.id), files.map(\.id), "Без превышения лимита список возвращается без изменений")
    }

    func testNegativeLimitBehavesLikeOne() {
        let files = (0..<2).map { makeFile(name: "f\($0)") }
        XCTAssertEqual(RecentFilesStore.applyingLimit(files, limit: -5).count, 1)
    }

    func testRecentFileCodableRoundtrip() throws {
        let file = makeFile(name: "codable")
        let data = try JSONEncoder().encode([file])
        let decoded = try JSONDecoder().decode([RecentFile].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].url, file.url)
        XCTAssertEqual(decoded[0].title, file.title)
    }

    // MARK: - Персист сортировки (SPEC R-HUB-8)

    func testSortOptionRawValueRoundtrip() {
        // Roundtrip через UserDefaults-представление (rawValue) — без касания
        // синглтона shared и реальных дефолтов приложения.
        for option in SortOption.allCases {
            let resolved = RecentFilesStore.resolveSortOption(raw: option.rawValue)
            XCTAssertEqual(resolved, option, "rawValue → SortOption должен восстанавливать \(option.rawValue)")
        }
    }

    func testSortOptionInvalidRawValueFallsBackToLastOpened() {
        XCTAssertEqual(RecentFilesStore.resolveSortOption(raw: "несуществующее"), .lastOpened)
        XCTAssertEqual(RecentFilesStore.resolveSortOption(raw: nil), .lastOpened)
    }

    // MARK: - Этап 5: контракт stale security-scoped bookmark

    /// Контракт доступа HubView.openRecentFile → AppState.openDocument:
    /// 1) bookmark создаётся с опцией .withSecurityScope (согласованность с
    ///    резолвом в openRecentFile);
    /// 2) свежий (не-stale) bookmark резолвится и открывает scoped-доступ;
    /// 3) refreshBookmarkData обновляет данные и переживает JSON-roundtrip.
    /// БЕЗ песочницы (D-25) start/stop — no-op, контракт фиксируется явно.
    func testSecurityBookmarkResolveAndRefreshContract() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fileURL = dir.appendingPathComponent("note.md")
        try "# Контракт".write(to: fileURL, atomically: true, encoding: .utf8)

        // 1) Bookmark с той же опцией, что в RecentFilesStore.addOrUpdate.
        let original = try fileURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)

        // 2) Резолв (как в HubView.openRecentFile) + scoped-доступ на время чтения.
        var isStale = false
        let resolved = try URL(resolvingBookmarkData: original, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        XCTAssertEqual(resolved.standardizedFileURL.path, fileURL.standardizedFileURL.path)
        let accessing = resolved.startAccessingSecurityScopedResource()
        let text = try String(contentsOf: resolved, encoding: .utf8)
        if accessing { resolved.stopAccessingSecurityScopedResource() }
        XCTAssertEqual(text, "# Контракт", "чтение между start/stop обязано проходить")
        XCTAssertFalse(isStale, "свежесозданный bookmark не должен быть stale")

        // 3) Refresh: новые данные эквивалентны и резолвятся в тот же файл.
        let refreshed = try fileURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        var isStaleAfterRefresh = false
        let resolvedRefreshed = try URL(resolvingBookmarkData: refreshed, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStaleAfterRefresh)
        XCTAssertEqual(resolvedRefreshed.standardizedFileURL.path, fileURL.standardizedFileURL.path)
        XCTAssertFalse(isStaleAfterRefresh)

        // JSON-roundtrip: bookmarkData переживает сериализацию (персист recent.json).
        let entry = RecentFile(url: fileURL, bookmarkData: refreshed, lastOpened: Date(), lastModified: Date(), title: "note", preview: "", wordCount: 0, fileSize: 1)
        let decoded = try JSONDecoder().decode([RecentFile].self, from: try JSONEncoder().encode([entry]))
        XCTAssertNotNil(decoded.first?.bookmarkData)
    }
}
