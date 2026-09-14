import Foundation

/// Режим вывода HTML-рендера (R3):
/// - `.preview` — интерактивный рендер для WKWebView: contenteditable,
///   data-атрибуты синхронизации и кнопки редактирования таблиц.
/// - `.export` — чистый статический HTML для экспорта (HTML/PDF файлы).
enum OutputMode {
    case preview
    case export
}

/// Результат резолва изображения (Этап 2, SPEC N-6/N-7):
/// - `.allowed(String)` — URL можно ставить в `src`;
/// - `.blocked(reason:)` — рендерить плейсхолдер БЕЗ `src` и БЕЗ URL
///   (причина — фиксированная строка из кода, не из входных данных).
enum ResolvedImage: Equatable {
    case allowed(String)
    case blocked(reason: String)
}

/// Простой экспорт Markdown → HTML на базе уже готовой блочной модели `MarkdownBlock`.
/// Используется для превью (`.preview`) и «Открыть как HTML»/PDF-экспорта (`.export`).
///
/// Этап 2 (SPEC N-6 — приватность):
/// - http/https-изображения по умолчанию НЕ ставятся в `src` (плейсхолдер);
///   включается тумблером «Загружать удалённые изображения» (SettingsStore.allowRemoteImages);
/// - `data:`-картинки разрешены только с `data:image/*`;
/// - ссылки: allowlist схем http/https/mailto и якорей `#`; `javascript:`/`file:`/`data:`
///   и прочие схемы рендерятся как текст, без `<a href>`.
enum MarkdownToHTML {
    /// Контекст рендера: проходит через все рекурсивные вызовы, чтобы baseURL
    /// и политика приватности не терялись во вложенных inline-элементах
    /// (раньше `**![alt](img.png)**` рендерился без baseURL — побочный фикс).
    private struct RenderContext {
        let mode: OutputMode
        /// URL файла документа (SPEC R-MD-9) для резолва относительных картинок.
        let baseURL: URL?
        /// Загружать ли удалённые (http/https) изображения. Default OFF (SPEC N-6).
        let allowRemoteImages: Bool
    }

    /// mode по умолчанию `.preview`: исторически все внутренние вызовы рендерили превью.
    /// baseURL (SPEC R-MD-9): URL документа — относительные пути изображений вида
    /// `![](путь/картинка.png)` резолвятся в absolute file://-URL относительно его папки.
    /// nil — пути не трогаются (тесты, документы без файла).
    /// allowRemoteImages: false — http(s)-изображения блокируются (плейсхолдер, SPEC N-6).
    static func convert(_ source: String, mode: OutputMode = .preview, baseURL: URL? = nil, allowRemoteImages: Bool = false) -> String {
        let blocks = MarkdownParser.shared.parse(source)
        let ctx = RenderContext(mode: mode, baseURL: baseURL, allowRemoteImages: allowRemoteImages)
        return blocks.map { render($0, ctx: ctx) }.joined()
    }

    private static func render(_ block: MarkdownBlock, ctx: RenderContext) -> String {
        // JS-специфичные атрибуты (синхронизация скролла/редактирование) — только превью.
        let lineAttr = (ctx.mode == .preview) ? (block.sourceLine.map { " data-source-line=\"\($0)\"" } ?? "") : ""
        let editable = (ctx.mode == .preview) ? " contenteditable=\"true\"" : ""
        switch block.content {
        case .heading(let level, let inline):
            return "<h\(level)\(lineAttr)\(editable)>\(inlineHTML(inline, ctx: ctx))</h\(level)>\n"

        case .paragraph(let inline):
            return "<p\(lineAttr)\(editable)>\(inlineHTML(inline, ctx: ctx))</p>\n"

        case .blockquote(let children):
            return "<blockquote\(lineAttr)>\n\(children.map { render($0, ctx: ctx) }.joined())</blockquote>\n"

        case .bulletList(let items):
            let body = items.map { itemBlocks in
                let liAttr = (ctx.mode == .preview && itemBlocks.first?.sourceLine != nil) ? " data-source-line=\"\(itemBlocks.first!.sourceLine!)\"" : ""
                return "<li\(liAttr)>\n\(itemBlocks.map { render($0, ctx: ctx) }.joined())</li>\n"
            }.joined()
            return "<ul\(lineAttr)>\n\(body)</ul>\n"

        case .orderedList(let items, _):
            let body = items.map { itemBlocks in
                let liAttr = (ctx.mode == .preview && itemBlocks.first?.sourceLine != nil) ? " data-source-line=\"\(itemBlocks.first!.sourceLine!)\"" : ""
                return "<li\(liAttr)>\n\(itemBlocks.map { render($0, ctx: ctx) }.joined())</li>\n"
            }.joined()
            return "<ol\(lineAttr)>\n\(body)</ol>\n"

        case .code(let language, let content):
            let lang = (language?.isEmpty == false ? " class=\"language-\(escape(language!))\"" : "")
            return "<pre\(lineAttr)><code\(lang)>\(escape(content))</code></pre>\n"

        case .thematicBreak:
            return "<hr\(lineAttr)>\n"

        case .table(let header, let rows, _):
            if ctx.mode == .preview {
                return renderInteractiveTable(block, header: header, rows: rows, lineAttr: lineAttr, ctx: ctx)
            }
            return renderPlainTable(header: header, rows: rows, ctx: ctx)

        case .html(let content):
            // Сырой HTML из документа не доверяем: экранируем, чтобы скрипты/атрибуты
            // не исполнялись в превью. Остальной markdown рендерится как раньше.
            let escaped = escape(content)
            if block.sourceLine != nil {
                return "<div\(lineAttr)>\(escaped)</div>\n"
            }
            return escaped
        }
    }

    /// Превью-таблица: contenteditable-ячейки, кнопки добавления/удаления строк и колонок.
    private static func renderInteractiveTable(_ block: MarkdownBlock, header: [[MarkdownInline]], rows: [[[MarkdownInline]]], lineAttr: String, ctx: RenderContext) -> String {
        let sourceLineNum = block.sourceLine ?? 0
        let head = header.enumerated().map { idx, cell in
            let delColBtn = "<button class=\"table-action-btn table-del-col\" data-col=\"\(idx)\" contenteditable=\"false\">−</button>"
            return "<th contenteditable=\"true\" data-row=\"0\" data-col=\"\(idx)\"\(alignAttr(idx))>\(delColBtn)<span class=\"cell-text\">\(inlineHTML(cell, ctx: ctx))</span></th>"
        }.joined()
        let body = rows.enumerated().map { rIdx, row in
            let tds = row.enumerated().map { cIdx, cell in
                let delRowBtn = cIdx == 0 ? "<button class=\"table-action-btn table-del-row\" data-row=\"\(rIdx + 1)\" contenteditable=\"false\">−</button>" : ""
                return "<td contenteditable=\"true\" data-row=\"\(rIdx + 1)\" data-col=\"\(cIdx)\"\(alignAttr(cIdx))>\(delRowBtn)<span class=\"cell-text\">\(inlineHTML(cell, ctx: ctx))</span></td>"
            }.joined()
            return "<tr data-source-line=\"\(sourceLineNum + 2 + rIdx)\">\(tds)</tr>"
        }.joined()

        return """
        <div class="table-container"\(lineAttr)>
        <table>
        <thead>
        <tr data-source-line=\"\(sourceLineNum)\">\(head)</tr>
        </thead>
        <tbody>\(body)</tbody>
        </table>
        <button class="table-action-btn table-add-row" data-source-line="\(sourceLineNum)" contenteditable=\"false\">+</button>
        <button class="table-action-btn table-add-col" data-source-line="\(sourceLineNum)" contenteditable=\"false\">+</button>
        </div>
        """
    }

    /// Экспорт-таблица: чистый статический HTML без UI-элементов редактирования.
    private static func renderPlainTable(header: [[MarkdownInline]], rows: [[[MarkdownInline]]], ctx: RenderContext) -> String {
        let head = header.map { cell in
            "<th>\(inlineHTML(cell, ctx: ctx))</th>"
        }.joined()
        let body = rows.map { row in
            let tds = row.map { cell in
                "<td>\(inlineHTML(cell, ctx: ctx))</td>"
            }.joined()
            return "<tr>\(tds)</tr>"
        }.joined()
        return """
        <table>
        <thead>
        <tr>\(head)</tr>
        </thead>
        <tbody>\(body)</tbody>
        </table>
        """
    }

    private static func alignAttr(_ idx: Int) -> String {
        // Пропускаем — базовый стиль; можно расширить позже.
        ""
    }

    private static func inlineHTML(_ inlines: [MarkdownInline], ctx: RenderContext) -> String {
        inlines.map { inline -> String in
            switch inline {
            case .text(let s): return escape(s)
            case .checkbox(let isChecked):
                // SPEC R-MD-4: чекбоксы интерактивны в preview (toggle через
                // checkboxToggleHandler → applyCheckboxToggle), статичный span ☐/☑
                // в export (печатается в PDF/HTML).
                if ctx.mode == .preview {
                    return "<input type=\"checkbox\" class=\"task-checkbox\"\(isChecked ? " checked" : "")>"
                }
                return "<span class=\"task-checkbox \(isChecked ? "checked" : "unchecked")\">\(isChecked ? "☑" : "☐")</span>"
            case .softBreak: return " "
            case .lineBreak: return "<br>"
            case .strong(let inner): return "<strong>\(inlineHTML(inner, ctx: ctx))</strong>"
            case .emphasis(let inner): return "<em>\(inlineHTML(inner, ctx: ctx))</em>"
            case .strikethrough(let inner): return "<del>\(inlineHTML(inner, ctx: ctx))</del>"
            case .code(let s): return "<code>\(escape(s))</code>"
            case .link(let inner, let url, _):
                // Этап 2 (SPEC N-6): allowlist схем. javascript:/file:/data:/vbscript:
                // и относительные пути — рендерим только текст, без <a href>.
                if let url, Self.isSafeLinkURL(url) {
                    return "<a href=\"\(escape(url))\">\(inlineHTML(inner, ctx: ctx))</a>"
                }
                return inlineHTML(inner, ctx: ctx)
            case .image(let alt, let url, _):
                return renderImage(alt: alt, url: url, ctx: ctx)
            }
        }.joined()
    }

    // MARK: - Ссылки (allowlist схем)

    /// Allowlist схем для ссылок (Этап 2): http, https, mailto и внутристраничные якоря `#`.
    /// Всё остальное (javascript:, file:, data:, vbscript:, неизвестные/относительные схемы)
    /// безопасной ссылкой не считается — рендерится как текст.
    static func isSafeLinkURL(_ url: String) -> Bool {
        let trimmed = url.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") { return true }
        guard let parsed = URL(string: trimmed), let scheme = parsed.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "mailto"
    }

    // MARK: - Изображения (SPEC R-MD-9 + Этап 2 security)

    private static func renderImage(alt: String, url: String?, ctx: RenderContext) -> String {
        // url == nil → `<img alt>` без src (прежнее поведение: атрибут не ставился).
        guard let url, !url.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "<img alt=\"\(escape(alt))\">"
        }
        switch Self.resolveImage(url, baseURL: ctx.baseURL, allowRemote: ctx.allowRemoteImages) {
        case .allowed(let src):
            // Этап 5 (404 файла): локальная картинка, прошедшая резолв (внутри
            // docDir), но отсутствующая на диске — плейсхолдер как у remote-block,
            // а не битый <img>: без src и БЕЗ пути в HTML (путь может содержать
            // PII). Проверка только для file:// — remote не тянется (SPEC N-6),
            // data:/относительный-src-без-baseURL не проверяются на диске.
            if src.hasPrefix("file://") {
                if let fileURL = URL(string: src), !FileManager.default.fileExists(atPath: fileURL.path) {
                    return "<span class=\"blocked-image\" title=\"\(escape(alt))\">🖼️ \(escape(alt)) — файл изображения не найден</span>"
                }
            }
            return "<img src=\"\(escape(src))\" alt=\"\(escape(alt))\">"
        case .blocked(let reason):
            // SPEC N-6/N-7: плейсхолдер без src и БЕЗ самого URL (URL может быть
            // трекинг-пикселем/PII). Выводим только alt и фиксированную причину.
            return "<span class=\"blocked-image\" title=\"\(escape(alt))\">🖼️ \(escape(alt)) — \(escape(reason))</span>"
        }
    }

    /// Резолв пути изображения (SPEC R-MD-9 + Этап 2):
    /// - http/https — только при `allowRemote` (тумблер Settings, default OFF, SPEC N-6);
    /// - `data:` — только `data:image/*`, остальное блокируется;
    /// - `file://` и абсолютные unix-пути — только ВНУТРИ папки документа
    ///   (path traversal-защита: `..`/`/etc/...` вне doc dir → блок);
    /// - относительный путь — посегментный резолв от папки документа,
    ///   выход выше папки документа — блок;
    /// - без baseURL относительные пути не трогаются (тесты, документы без файла),
    ///   абсолютные и file:// без baseURL — блок.
    static func resolveImage(_ path: String, baseURL: URL?, allowRemote: Bool = false) -> ResolvedImage {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .blocked(reason: "пустой путь изображения") }
        let lower = trimmed.lowercased()

        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return allowRemote ? .allowed(trimmed) : .blocked(reason: "удалённый ресурс заблокирован")
        }
        if lower.hasPrefix("data:") {
            // Разрешаем только data:image/* (data:image/png;base64,... и т.п.).
            if trimmed.dropFirst("data:".count).lowercased().hasPrefix("image/") {
                return .allowed(trimmed)
            }
            return .blocked(reason: "data:URI не-изображение заблокировано")
        }
        // Дальше — локальные пути; папка документа нужна как граница доверия.
        guard let base = baseURL else {
            if !lower.hasPrefix("file://") && !trimmed.hasPrefix("/") {
                return .allowed(trimmed)
            }
            return .blocked(reason: "локальный путь без папки документа заблокирован")
        }
        let docDir = base.deletingLastPathComponent().standardizedFileURL

        if lower.hasPrefix("file://") {
            guard let fileURL = URL(string: trimmed), fileURL.isFileURL else {
                return .blocked(reason: "невалидный file://URL заблокирован")
            }
            let target = fileURL.standardizedFileURL
            guard Self.isInside(target, of: docDir) else {
                return .blocked(reason: "изображение вне папки документа заблокировано")
            }
            return .allowed(target.absoluteString)
        }
        if trimmed.hasPrefix("/") {
            // Абсолютный unix-путь больше не пропускается «как есть» (Этап 2).
            let target = URL(fileURLWithPath: trimmed).standardizedFileURL
            guard Self.isInside(target, of: docDir) else {
                return .blocked(reason: "изображение вне папки документа заблокировано")
            }
            return .allowed(target.absoluteString)
        }
        // Относительный путь: «sub/x.png» — по сегментам (appendingPathComponent
        // трактовал бы «sub/x.png» как один компонент); «..» поднимается, но не выше docDir.
        var dir = docDir
        for segment in trimmed.split(separator: "/") {
            if segment == ".." {
                dir.deleteLastPathComponent()
            } else if segment == "." {
                continue
            } else {
                dir.appendPathComponent(String(segment))
            }
        }
        let resolved = dir.standardizedFileURL
        guard Self.isInside(resolved, of: docDir) else {
            return .blocked(reason: "изображение вне папки документа заблокировано")
        }
        return .allowed(resolved.absoluteString)
    }

    /// Проверка «url внутри dir» по path-префиксу с границей компонента пути
    /// (/tmp/docs не матчит /tmp/docs-evil/...).
    static func isInside(_ url: URL, of dir: URL) -> Bool {
        let p = url.path
        let d = dir.path
        guard p.hasPrefix(d) else { return false }
        let rest = p.dropFirst(d.count)
        return rest.isEmpty || rest.hasPrefix("/")
    }

    private static func escape(_ s: String) -> String {
        // Сущности собираются конкатенацией ("&" + "lt;"), чтобы литералы
        // сущностей не декодировались при записи файла (см. MarkdownToHTMLTests).
        s.replacingOccurrences(of: "&", with: "&" + "amp;")
         .replacingOccurrences(of: "<", with: "&" + "lt;")
         .replacingOccurrences(of: ">", with: "&" + "gt;")
         .replacingOccurrences(of: "\"", with: "&" + "quot;")
    }
}
