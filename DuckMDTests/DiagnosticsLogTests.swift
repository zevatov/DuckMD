import XCTest
import os
@testable import DuckMD

/// G-DIAG: sanity-тесты диагностического слоя Unified Logging.
/// os.Logger не читается из процесса, поэтому проверяем инварианты конфигурации:
/// единый subsystem, набор категорий, безопасные хелперы метаданных.
final class DiagnosticsLogTests: XCTestCase {

    func testSubsystemMatchesBundleIDNamespace() {
        XCTAssertEqual(Diag.subsystem, "net.duckmd.DuckMD")
    }

    func testAllCategoriesCreated() {
        // Создание Logger не падает; пять категорий сконфигурированы.
        let loggers: [Logger] = [Diag.app, Diag.file, Diag.watcher, Diag.preview, Diag.export]
        XCTAssertEqual(loggers.count, 5)
    }

    func testExtHelperIsPublicSafeMetadata() {
        let url = URL(fileURLWithPath: "/tmp/private/doc.MD")
        XCTAssertEqual(Diag.ext(url), "md")
        let noExt = URL(fileURLWithPath: "/tmp/private/noext")
        XCTAssertEqual(Diag.ext(noExt), "")
    }

    func testLogCallWithPrivacySpecifiersCompiles() {
        // Smoke: вызов с privacy-спецификаторами не крэшится (инвариант API).
        Diag.file.info("тест: bytes=\(1, privacy: .public), path=\("/tmp/x.md", privacy: .private)")
    }
}
