import XCTest
import UniformTypeIdentifiers
@testable import DuckMD

/// Регресс-тесты двух пользовательских проблем:
/// 1. Ассоциация .md: DuckMD заявляет ТОЛЬКО системный тип
///    net.daringfireball.markdown (без собственного exported-типа — раньше
///    опечатка net.duckingfireball.markdown конкурировала за расширение .md
///    и ломала открытие двойным кликом из Finder).
/// 2. Живой preview: первичный рендер синхронен и учитывает documentURL;
///    light-тема фиксирует светлый вариант CSS (белый фон/тёмный текст),
///    dark — тёмный, system — прежний @media-автопереключатель.
final class DocumentAssociationAndThemeTests: XCTestCase {

    // MARK: - UTType / file association

    func testMarkdownDocIsSystemMarkdownType() {
        XCTAssertEqual(UTType.markdownDoc.identifier, "net.daringfireball.markdown")
        XCTAssertEqual(UTType.markdownStandard.identifier, "net.daringfireball.markdown")
    }

    func testMarkdownTypeHandlesMDExtensionAndText() {
        XCTAssertEqual(UTType.markdownDoc.preferredFilenameExtension, "md")
        XCTAssertTrue(UTType.markdownDoc.conforms(to: .plainText))
    }

    /// Этап 5: readableContentTypes ПО-ПРЕЖНЕМУ принимает .txt на вход
    /// (чтение из «Открыть…»/drag&drop), но ассоциация (владение) — только .md.
    func testReadableContentTypesIncludeMarkdownAndPlainText() {
        let types = MarkdownDocument.readableContentTypes.map(\.identifier)
        XCTAssertTrue(types.contains("net.daringfireball.markdown"))
        XCTAssertTrue(types.contains(UTType.plainText.identifier))
        // Опечаточный тип не должен остаться нигде в рантайме.
        XCTAssertFalse(types.contains("net.duckingfireball.markdown"))
    }

    /// Этап 5 (контракт TXT не-owner): CFBundleDocumentTypes заявляет ТОЛЬКО
    /// системный markdown-тип; public.plain-text больше не объявляется как
    /// владение (раньше LSHandlerRank: Owner перехватывал TXT у TextEdit).
    /// Чтение .txt остаётся возможным: readableContentTypes включает plainText
    /// (см. testReadableContentTypesIncludeMarkdownAndPlainText), вход
    /// конвертера задан явно allowedContentTypes (R-CONV-1/R-HUB-5).
    func testBundleDocumentTypesOwnMarkdownOnlyNotPlainText() throws {
        // TEST_HOST — приложение DuckMD: Bundle.main.infoDictionary —
        // это разобранный Info.plist приложения (генерируется xcodegen из project.yml).
        let docTypes = (Bundle.main.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]]) ?? []
        XCTAssertFalse(docTypes.isEmpty, "CFBundleDocumentTypes обязан присутствовать в Info.plist приложения")

        let allContentTypes = docTypes.flatMap { ($0["LSItemContentTypes"] as? [String]) ?? [] }
        XCTAssertTrue(allContentTypes.contains("net.daringfireball.markdown"),
                      "DuckMD обязан оставаться владельцем .md: \(allContentTypes)")
        XCTAssertFalse(allContentTypes.contains("public.plain-text"),
                       "TXT не должен быть во владении приложения (Этап 5): \(allContentTypes)")

        for docType in docTypes where (docType["LSItemContentTypes"] as? [String])?.contains("net.daringfireball.markdown") == true {
            XCTAssertEqual(docType["LSHandlerRank"] as? String, "Owner",
                           "Markdown-запись обязана держать Owner: \(docType)")
            XCTAssertEqual(docType["CFBundleTypeRole"] as? String, "Editor")
        }
    }

    // MARK: - Первичный render (проблема «пустой preview при открытии»)

    func testInitProducesNonEmptyPrimaryHTMLImmediately() {
        let doc = MarkdownDocument(text: "# Заголовок\n\nАбзац")
        XCTAssertFalse(doc.renderedHTML.isEmpty, "renderedHTML обязан быть готов сразу после init")
        XCTAssertTrue(doc.renderedHTML.contains("<h1"))
        XCTAssertFalse(doc.parsedBlocks.isEmpty)
    }

    func testInitWithDocumentURLResolvesRelativeImagesInPrimaryRender() throws {
        // Этап 5 (404): резолв проверяется на СУЩЕСТВУЮЩЕЙ картинке (temp) —
        // отсутствующий файл теперь даёт плейсхолдер, а не <img>.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89]).write(to: dir.appendingPathComponent("pic.png"))

        let doc = MarkdownDocument(
            text: "![](pic.png)",
            documentURL: dir.appendingPathComponent("notes.md"))
        XCTAssertTrue(
            doc.renderedHTML.contains("src=\"file://"),
            "первичный рендер должен резолвить существующую относительную картинку от папки документа: \(doc.renderedHTML)")
        // blocked-image — CSS-класс шаблона buildFullHTML, поэтому проверяем
        // отсутствие именно 404-плейсхолдера, а не строки класса.
        XCTAssertFalse(doc.renderedHTML.contains("файл изображения не найден"))
    }

    func testInitWithoutDocumentURLKeepsRelativePathAsIs() {
        let doc = MarkdownDocument(text: "![](pic.png)")
        XCTAssertTrue(doc.renderedHTML.contains("src=\"pic.png\""))
    }

    func testRegenerateHTMLAppliesNewThemeAndKeepsDocumentURL() throws {
        // Этап 5 (404): картинка должна существовать на диске (temp).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89]).write(to: dir.appendingPathComponent("pic.png"))

        let doc = MarkdownDocument(
            text: "![](pic.png)",
            theme: .neutral,
            documentURL: dir.appendingPathComponent("notes.md"))
        XCTAssertTrue(doc.renderedHTML.contains("src=\"file://"))

        let light = HTMLTheme(
            cssBody: "body { background-color: #ffffff; color: #111111; }",
            fontSize: 16)
        doc.regenerateHTML(theme: light)
        // regenerateHTML асинхронен (background → main); ждём главный цикл.
        let exp = expectation(description: "regenerateHTML applied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertTrue(doc.renderedHTML.contains("background-color: #ffffff"))
        XCTAssertTrue(doc.renderedHTML.contains("src=\"file://"),
                      "резолв существующих картинок должен переживать смену темы")
        // blocked-image — CSS-класс шаблона; проверяем отсутствие 404-плейсхолдера.
        XCTAssertFalse(doc.renderedHTML.contains("файл изображения не найден"),
                       "существующая картинка не должна блокироваться после смены темы")
    }

    // MARK: - Темы preview: light контрастность / dark без поломок

    func testLightThemePinsLightCSSWithoutMediaQuery() {
        let css = RenderThemeOption.apple.cssBody(for: .light)
        XCTAssertFalse(css.contains("@media"), "light должен быть зафиксирован без @media")
        XCTAssertTrue(css.contains("background-color: #ffffff"), "светлая тема — белый фон")
        XCTAssertTrue(css.contains("color: #1d1d1f"), "светлая тема — тёмный текст")
    }

    func testDarkThemePinsDarkCSSWithoutMediaQuery() {
        let css = RenderThemeOption.apple.cssBody(for: .dark)
        XCTAssertFalse(css.contains("@media"), "dark должен быть зафиксирован без @media")
        XCTAssertTrue(css.contains("background-color: #1c1c1e"), "тёмная тема — тёмный фон")
        XCTAssertTrue(css.contains("color: #f5f5f7"), "тёмная тема — светлый текст")
    }

    func testSystemThemeKeepsMediaAutoSwitch() {
        let css = RenderThemeOption.apple.cssBody(for: .system)
        XCTAssertTrue(css.contains("@media (prefers-color-scheme: light)"))
        XCTAssertTrue(css.contains("@media (prefers-color-scheme: dark)"))
    }

    func testResolvedThemeMatchesSelectedAppThemeMode() {
        // .resolved() читает SettingsStore; проверяем согласованность фиксации
        // варианта с текущим режимом темы приложения без мутации настроек.
        let theme = HTMLTheme.resolved()
        let mode = SettingsStore.shared.theme
        if mode == .light {
            XCTAssertFalse(theme.cssBody.contains("@media"))
            XCTAssertTrue(theme.cssBody.contains("background-color: #ffffff"))
        } else if mode == .dark {
            XCTAssertFalse(theme.cssBody.contains("@media"))
            XCTAssertTrue(theme.cssBody.contains("background-color: #1c1c1e"))
        } else {
            XCTAssertTrue(theme.cssBody.contains("@media"))
        }
    }

    // MARK: - buildFullHTML: целостность шаблона

    func testBuildFullHTMLContainsMarkerAndBody() {
        let html = MarkdownDocument.buildFullHTML(from: "# T", theme: .neutral, baseURL: nil)
        XCTAssertTrue(html.contains(HTMLTheme.bodyMarker))
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("</html>"))
    }
}
