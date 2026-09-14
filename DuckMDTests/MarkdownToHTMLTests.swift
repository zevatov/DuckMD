import XCTest
@testable import DuckMD

/// R10: тесты MarkdownToHTML — режимы OutputMode (.preview vs .export)
/// и XSS-регресс (raw HTML не должен попадать в вывод неэкранированным).
/// Примечание: HTML-сущности собираются конкатенацией ("&" + "lt;"), чтобы
/// литералы сущностей не декодировались при записи файла.
final class MarkdownToHTMLTests: XCTestCase {

    /// "<" — экранированный символ "<"
    private var entityLT: String { "&" + "lt;" }
    /// ">" — экранированный символ ">"
    private var entityGT: String { "&" + "gt;" }

    // MARK: - OutputMode

    func testPreviewContainsEditableAndSourceLine() {
        let html = MarkdownToHTML.convert("# Привет", mode: .preview)
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("contenteditable=\"true\""), "preview обязан быть редактируемым")
        XCTAssertTrue(html.contains("data-source-line=\"1\""), "preview обязан нести data-source-line")
    }

    func testExportIsStaticHTML() {
        let html = MarkdownToHTML.convert("# Привет\n\nАбзац", mode: .export)
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("<p>"))
        XCTAssertFalse(html.contains("contenteditable"), "export не должен содержать contenteditable")
        XCTAssertFalse(html.contains("data-source-line"), "export не должен содержать data-source-line")
        XCTAssertFalse(html.contains("<button"), "export не должен содержать UI-кнопки")
    }

    func testTableEditingUIOnlyInPreview() {
        let src = "| A | B |\n|---|---|\n| 1 | 2 |"
        let preview = MarkdownToHTML.convert(src, mode: .preview)
        XCTAssertTrue(preview.contains("table-add-row"))
        XCTAssertTrue(preview.contains("table-del-row"))

        let export = MarkdownToHTML.convert(src, mode: .export)
        XCTAssertTrue(export.contains("<table>"))
        XCTAssertFalse(export.contains("<button"))
        XCTAssertFalse(export.contains("table-action-btn"))
    }

    // MARK: - XSS-регресс

    func testRawHTMLBlockIsEscapedInPreview() {
        let html = MarkdownToHTML.convert("<script>alert(1)</script>", mode: .preview)
        XCTAssertFalse(html.contains("<script>"), "raw <script> не должен попасть в вывод неэкранированным")
        XCTAssertTrue(html.contains(entityLT + "script" + entityGT), "raw HTML должен быть экранирован в \(html)")
    }

    func testRawHTMLBlockIsEscapedInExport() {
        let html = MarkdownToHTML.convert("<script>alert(1)</script>", mode: .export)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains(entityLT + "script" + entityGT), "raw HTML должен быть экранирован в \(html)")
    }

    func testInlineScriptIsDropped() {
        let html = MarkdownToHTML.convert("Текст <script>alert(1)</script> конец", mode: .preview)
        XCTAssertFalse(html.contains("<script>"), "инлайновый <script> не должен рендериться")
    }

    func testCodeBlockContentIsEscaped() {
        let html = MarkdownToHTML.convert("```\n<script>alert(1)</script>\n```", mode: .export)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains(entityLT + "script" + entityGT), "код должен быть экранирован в \(html)")
    }

    func testAngleBracketsInTextAreEscaped() {
        let html = MarkdownToHTML.convert("Сравнение 5 < 10 и 10 > 5", mode: .export)
        XCTAssertTrue(html.contains(entityLT), "голый '<' должен быть экранирован в \(html)")
        XCTAssertTrue(html.contains(entityGT), "голый '>' должен быть экранирован в \(html)")
        XCTAssertFalse(html.contains("<10"), "голый текст с '<' не должен стать тегом")
    }

    // MARK: - Task list чекбоксы (SPEC R-MD-4)

    func testTaskCheckboxRenderedInPreviewAndExport() {
        let src = "- [ ] открытый\n- [x] закрытый"
        let preview = MarkdownToHTML.convert(src, mode: .preview)
        XCTAssertTrue(preview.contains("type=\"checkbox\""), "preview: чекбокс рендерится input-ом в \(preview)")
        XCTAssertTrue(preview.contains("task-checkbox"), "preview: должен нести CSS-класс task-checkbox")
        XCTAssertTrue(preview.contains(" checked"), "checked-пункт должен иметь checked-атрибут в \(preview)")

        let export = MarkdownToHTML.convert(src, mode: .export)
        XCTAssertFalse(export.contains("<input"), "export: не должно быть input-элементов в \(export)")
        XCTAssertTrue(export.contains("task-checkbox"), "export: должен нести CSS-класс task-checkbox")
        XCTAssertTrue(export.contains("☑"), "export: checked отображается ☑ в \(export)")
        XCTAssertTrue(export.contains("☐"), "export: unchecked отображается ☐ в \(export)")
    }

    func testRegularListNotRenderedAsCheckbox() {
        let preview = MarkdownToHTML.convert("- обычный пункт", mode: .preview)
        XCTAssertFalse(preview.contains("task-checkbox"), "обычный список не должен рендериться чекбоксом")
    }

    // MARK: - Локальные изображения (SPEC R-MD-9)

    func testRelativeImagePathResolvedAgainstDocumentURL() throws {
        // Этап 5 (404): для рендера нужен существующий файл — кириллица+пробел
        // в имени создаются физически, резолв проверяет percent-encoding.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("pics", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89]).write(to: dir.appendingPathComponent("pics/фото 1.png"))

        let doc = dir.appendingPathComponent("note.md")
        // Валидный CommonMark: пробел/кириллица в URL требуют <>-обёртки.
        let html = MarkdownToHTML.convert("![alt](<pics/фото 1.png>)", mode: .preview, baseURL: doc)
        // Путь резолвится в file://-URL папки документа; спецсимволы — percent-encoded.
        XCTAssertTrue(html.contains("src=\"file://") && html.contains("%D1%84%D0%BE%D1%82%D0%BE%201.png"), "относительный путь должен стать абсолютным percent-encoded file://-URL в \(html)")
        XCTAssertFalse(html.contains("файл изображения не найден"), "существующая картинка не должна блокироваться: \(html)")
    }

    func testRelativeImagePathWithoutSpaces() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("pics", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89]).write(to: dir.appendingPathComponent("pics/kartinka.png"))

        let doc = dir.appendingPathComponent("note.md")
        let html = MarkdownToHTML.convert("![alt](pics/kartinka.png)", mode: .preview, baseURL: doc)
        XCTAssertTrue(html.contains("src=\"file://") && html.contains("pics/kartinka.png"), "в \(html)")
        XCTAssertFalse(html.contains("файл изображения не найден"), "существующая картинка не должна блокироваться: \(html)")
    }

    // Этап 2: старые кейсы file:// вне doc dir теперь блокируются — перенесены
    // в security-секцию ниже. Кейсы data:image остаются легитимными.

    func testDataImageAllowed() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![b](data:image/png;base64,AAA)", mode: .export, baseURL: doc)
        XCTAssertTrue(html.contains("src=\"data:image/png;base64,AAA\""))
    }

    func testRelativePathWithoutBaseURLStaysRelative() {
        let html = MarkdownToHTML.convert("![a](img.png)", mode: .preview)
        XCTAssertTrue(html.contains("src=\"img.png\""), "без baseURL пути не должны трогаться в \(html)")
    }

    // MARK: - Этап 2: Security (SPEC N-6, path traversal)

    func testRemoteImageBlockedByDefault() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![a](https://ex.com/i.png)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("<img"), "удалённая картинка не должна попасть в src при default OFF: \(html)")
        XCTAssertFalse(html.contains("https://ex.com"), "URL заблокированного ресурса не должен утечь в HTML: \(html)")
        XCTAssertTrue(html.contains("blocked-image"), "должен быть плейсхолдер: \(html)")
        XCTAssertTrue(html.contains("удалённый ресурс заблокирован"), "плейсхолдер должен содержать пометку: \(html)")
        XCTAssertTrue(html.contains("title=\"a\""), "alt должен сохраниться в плейсхолдере (title): \(html)")
    }

    func testRemoteImageAllowedWithToggle() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![a](http://ex.com/pixel.png)", mode: .preview, baseURL: doc, allowRemoteImages: true)
        XCTAssertTrue(html.contains("src=\"http://ex.com/pixel.png\""), "тумблер ON разрешает http-картинку: \(html)")
    }

    func testDataImageNonImageBlocked() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![x](data:text/html;base64,PHNjcmlwdD4=)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("src="), "data: не-image не должен попасть в src: \(html)")
        XCTAssertTrue(html.contains("blocked-image"), "должен быть плейсхолдер: \(html)")
    }

    func testPathTraversalRelativeBlocked() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![s](../secret.png)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("secret.png"), "выход выше папки документа запрещён: \(html)")
        XCTAssertFalse(html.contains("<img"), "должен быть плейсхолдер: \(html)")
        XCTAssertTrue(html.contains("blocked-image"), "должен быть плейсхолдер: \(html)")
    }

    func testFileURLInsideDocDirAllowed() throws {
        // Этап 5 (404): существующие картинки рендерятся как <img>, поэтому
        // кейс создаёт реальный файл в temp (раньше путь был фиктивным).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("pics", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pic = dir.appendingPathComponent("pics/ok.png")
        try Data([0x89]).write(to: pic)

        let doc = dir.appendingPathComponent("note.md")
        let html = MarkdownToHTML.convert("![ok](file://\(pic.path))", mode: .preview, baseURL: doc)
        XCTAssertTrue(html.contains("src=\"file://"), "file:// внутри doc dir с существующим файлом легитимен: \(html)")
        XCTAssertFalse(html.contains("blocked-image"), "существующая картинка не должна блокироваться: \(html)")
    }

    func testFileURLOutsideDocDirBlocked() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![p](file:///etc/passwd)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("/etc/passwd"), "file:// вне doc dir должен быть заблокирован: \(html)")
        XCTAssertTrue(html.contains("blocked-image"), "должен быть плейсхолдер: \(html)")
    }

    func testAbsoluteUnixPathOutsideDocDirBlocked() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![p](/etc/passwd)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("/etc/passwd"), "абсолютный путь вне doc dir больше не пропускается как есть: \(html)")
        XCTAssertTrue(html.contains("blocked-image"), "должен быть плейсхолдер: \(html)")
    }

    func testAbsoluteUnixPathInsideDocDirAllowed() throws {
        // Этап 5 (404): для рендера нужен реально существующий файл (temp).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("pics", isDirectory: true), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pic = dir.appendingPathComponent("pics/x.png")
        try Data([0x89]).write(to: pic)

        let doc = dir.appendingPathComponent("note.md")
        let html = MarkdownToHTML.convert("![p](\(pic.path))", mode: .preview, baseURL: doc)
        XCTAssertTrue(html.contains("src=\"file://"), "абсолютный путь внутри doc dir легитимен: \(html)")
        XCTAssertFalse(html.contains("blocked-image"), "существующая картинка не должна блокироваться: \(html)")
    }

    func testTraversalSiblingDirBlocked() {
        // /tmp/docs ≠ /tmp/docs-evil: проверка границы компонента пути.
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![s](../docs-evil/x.png)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("docs-evil"), "sibling-директория не должна проходить префикс-проверку: \(html)")
        XCTAssertTrue(html.contains("blocked-image"))
    }

    // MARK: - Этап 5: 404 отсутствующей локальной картинки

    /// Отсутствующий файл внутри docDir (404) — плейсхолдер как у remote-block:
    /// без src и БЕЗ пути/имени в HTML (путь может содержать PII).
    func testMissingLocalImageInsideDocDirGetsPlaceholderWithoutPathLeak() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        let html = MarkdownToHTML.convert("![фото](pics/missing-\(UUID().uuidString).png)", mode: .preview, baseURL: doc)
        XCTAssertFalse(html.contains("<img"), "404-файл не должен рендериться как img: \(html)")
        XCTAssertFalse(html.contains("src="), "404-плейсхолдер не должен нести src: \(html)")
        XCTAssertFalse(html.contains("missing-"), "имя 404-файла не должно утечь в HTML: \(html)")
        XCTAssertTrue(html.contains("blocked-image"), "должен быть плейсхолдер: \(html)")
        XCTAssertTrue(html.contains("файл изображения не найден"), "причина 404 должна быть видна: \(html)")
        XCTAssertTrue(html.contains("title=\"фото\""), "alt сохраняется в плейсхолдере: \(html)")
    }

    /// Существующая относительная картинка внутри docDir — обычный <img>.
    func testExistingRelativeImageInsideDocDirRenders() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DuckMDTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data([0x89]).write(to: dir.appendingPathComponent("pic.png"))

        let doc = dir.appendingPathComponent("note.md")
        let html = MarkdownToHTML.convert("![ок](pic.png)", mode: .preview, baseURL: doc)
        XCTAssertTrue(html.contains("<img src=\"file://"), "существующая относительная картинка рендерится: \(html)")
        XCTAssertFalse(html.contains("blocked-image"), "существующая картинка не блокируется: \(html)")
    }

    func testResolveImageUnitCases() {
        let doc = URL(fileURLWithPath: "/tmp/docs/note.md")
        XCTAssertEqual(MarkdownToHTML.resolveImage("", baseURL: doc), .blocked(reason: "пустой путь изображения"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("../secret.png", baseURL: doc), .blocked(reason: "изображение вне папки документа заблокировано"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("file:///etc/passwd", baseURL: doc), .blocked(reason: "изображение вне папки документа заблокировано"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("/abs/x.png", baseURL: doc), .blocked(reason: "изображение вне папки документа заблокировано"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("/tmp/docs/x.png", baseURL: doc), .allowed("file:///tmp/docs/x.png"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("http://e/x.png", baseURL: doc, allowRemote: true), .allowed("http://e/x.png"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("http://e/x.png", baseURL: doc), .blocked(reason: "удалённый ресурс заблокирован"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("data:text/html;base64,AAA", baseURL: doc), .blocked(reason: "data:URI не-изображение заблокировано"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("data:image/png;base64,AAA", baseURL: doc), .allowed("data:image/png;base64,AAA"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("sub/x.png", baseURL: doc), .allowed("file:///tmp/docs/sub/x.png"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("x.png", baseURL: nil), .allowed("x.png"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("file:///etc/x.png", baseURL: nil), .blocked(reason: "локальный путь без папки документа заблокирован"))
        XCTAssertEqual(MarkdownToHTML.resolveImage("/etc/x.png", baseURL: nil), .blocked(reason: "локальный путь без папки документа заблокирован"))
    }

    // MARK: - Этап 2: allowlist схем ссылок

    func testJavascriptLinkRenderedAsText() {
        let html = MarkdownToHTML.convert("[click](javascript:alert(1))", mode: .preview)
        XCTAssertFalse(html.contains("<a href"), "javascript:-ссылка не должна рендериться как <a href>: \(html)")
        XCTAssertTrue(html.contains("click"), "текст ссылки должен остаться: \(html)")
    }

    func testFileAndDataLinksRenderedAsText() {
        let html = MarkdownToHTML.convert("[f](file:///etc/passwd) и [d](data:text/html,x)", mode: .preview)
        XCTAssertFalse(html.contains("<a href"), "file:/data:-ссылки не должны стать <a href>: \(html)")
        XCTAssertTrue(html.contains("f") && html.contains("d"))
    }

    func testSafeLinksRenderedAsAnchors() {
        let html = MarkdownToHTML.convert("[a](https://ex.com) [b](http://ex.com) [c](mailto:a@b.co) [d](#section)", mode: .preview)
        XCTAssertTrue(html.contains("<a href=\"https://ex.com\">"))
        XCTAssertTrue(html.contains("<a href=\"http://ex.com\">"))
        XCTAssertTrue(html.contains("<a href=\"mailto:a@b.co\">"))
        XCTAssertTrue(html.contains("<a href=\"#section\">"))
    }

    func testRelativeLinkRenderedAsText() {
        // Относительные пути в ссылках небезопасны как href (неконтролируемая схема)
        // — рендерим как текст.
        let html = MarkdownToHTML.convert("[r](other/page.md)", mode: .preview)
        XCTAssertFalse(html.contains("<a href"), "относительная ссылка не должна стать <a href>: \(html)")
    }
}
