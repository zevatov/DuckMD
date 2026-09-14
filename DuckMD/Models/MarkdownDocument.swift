import Foundation
import SwiftUI
import UniformTypeIdentifiers
import Combine

// UTType для Markdown: единый СИСТЕМНЫЙ тип (встроен в macOS 12+; deployment
// target — macOS 26). Раньше здесь были exportedAs "net.duckingfireball.markdown"
// (опечатка в идентификаторе) и importedAs-копия — дублирующие заявки на
// расширение .md конфликтовали с системным типом, и Finder не открывал .md
// двойным кликом. Владелец .md — CFBundleDocumentTypes (LSHandlerRank: Owner).
extension UTType {
    /// Системный Markdown-тип.
    static let markdownDoc = UTType("net.daringfireball.markdown") ?? .plainText
    /// Псевдоним совместимости для существующих мест вызова (панели open/save).
    static let markdownStandard = UTType("net.daringfireball.markdown") ?? .plainText
}

/// Документ Markdown. Класс (`ReferenceFileDocument`) нужен, чтобы правки
/// текста мгновенно распространялись между рендером и режимом кода, а DocumentGroup
/// автоматически сохранял файл. `@Published` даёт реактивность для SwiftUI.
final class MarkdownDocument: ObservableObject, ReferenceFileDocument {
    static var readableContentTypes: [UTType] { [.markdownDoc, .markdownStandard, .plainText] }

    /// Снимок для сохранения — Sendable (String и так Sendable).
    typealias Snapshot = String

    /// Текущий текст документа (единый источник правды для рендера и редактора).
    @Published var text: String

    /// Предыдущий текст до авто-перезагрузки (для отката).
    @Published var previousText: String? = nil

    /// Список отпарсенных блоков, обновляемых с дебаунсом в фоновом потоке
    @Published var parsedBlocks: [MarkdownBlock] = []

    /// Готовый HTML для WKWebView-рендерера, обновляется с дебаунсом
    @Published var renderedHTML: String = ""

    /// Этап 3: монотонный номер поколения запланированного парсинга. Каждый
    /// запрос пересборки (первичный, debounce текста, смена темы) инкрементирует
    /// счётчик на main; фоновый результат применяется только если его поколение
    /// всё ещё актуально (`applyParseResult`) — иначе поздние фоновые задачи
    /// завершались не по порядку и затирали свежий `renderedHTML` устаревшим.
    private(set) var parseGeneration: Int = 0

    /// Этап 3: порог «большого» документа (байты): первичный parse/buildFullHTML
    /// уходит в фон, на экране — быстрый shell (CSS темы, пустое тело).
    static let largeDocumentByteThreshold = 256 * 1024
    /// Этап 3: порог «большого» документа (строки) — альтернативное условие.
    static let largeDocumentLineThreshold = 4000

    /// SPEC R-MD-9: URL файла документа — для резолва относительных путей
    /// изображений (`![](путь/картинка.png)`) при рендере. nil для новых
    /// документов и тестов; выставляется при открытии/сохранении файла.
    var documentURL: URL? = nil

    /// Снимок оформления превью (R5): резолвится в App/View-слое,
    /// модель отделена от хранилища настроек приложения.
    private var currentTheme: HTMLTheme = .neutral

    private var cancellables = Set<AnyCancellable>()

    init(text: String = "", theme: HTMLTheme = .neutral, documentURL: URL? = nil) {
        self.text = text
        self.currentTheme = theme
        // SPEC R-MD-9: URL известен ДО первого рендера — относительные пути
        // картинок резолвятся уже в синхронном первичном HTML (раньше URL
        // присваивался после init, и первичный рендер шёл без baseURL).
        self.documentURL = documentURL
        setupParsing()
    }

    /// Этап 1: явная ошибка на невалидном UTF-8 вместо пустой строки.
    /// Пустая строка позволяла пустому автосейву затeреть оригинал.
    /// Кидает `CocoaError.fileReadInapplicableStringEncoding` — вызывающий
    /// слой (`AppState.openDocument`) показывает явную ошибку и не создаёт
    /// документ (автосейв не запускается).
    required init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        guard let decoded = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        self.text = decoded
        setupParsing()
    }

    private func setupParsing() {
        // Этап 3: маленькие документы — как раньше, синхронный первичный HTML
        // (быстрый первый кадр; тесты DocumentAssociationAndThemeTests живут на
        // этом контракте). Большие — фоновый первичный parse под shell (см.
        // shell в ContentView — renderedHTML "" рисует подложку темы, не белый
        // экран навсегда: результат придёт через applyParseResult).
        if Self.isLargeDocument(text) {
            scheduleReparse(text: text)
        } else {
            self.parsedBlocks = MarkdownParser.shared.parse(self.text)
            self.renderedHTML = Self.buildFullHTML(from: self.text, theme: currentTheme, baseURL: documentURL)
        }

        // R5: реакция на смену настроек перенесена в View-слой
        // (ContentView → regenerateHTML(theme:)). Здесь — только text.
        // Этап 3: тяжёлая работа ушла в scheduleReparse (фон + generation).
        $text
            .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
            .sink { [weak self] text in
                self?.scheduleReparse(text: text)
            }
            .store(in: &cancellables)
    }

    /// Этап 3: единая точка планирования пересборки blocks+HTML. Снимок
    /// (theme/url/generation/text) делается на main ДО ухода в фон — прежнее
    /// чтение `currentTheme`/`documentURL` в map-замыкании на background было
    /// data race. Результат применяется на main только при актуальном поколении
    /// (`applyParseResult`/`applyHTMLResult`) — поздние фоновые задачи больше
    /// не затирают свежий renderedHTML устаревшим.
    /// Вызывается только с main (init, RunLoop.main).
    /// - Parameter includeBlocks: false — текст не менялся (смена темы), блоки
    ///   не пересчитываются (иначе смена темы дважды парсила бы большие файлы).
    private func scheduleReparse(text: String, includeBlocks: Bool = true) {
        let theme = currentTheme
        let baseURL = documentURL
        parseGeneration += 1
        let generation = parseGeneration
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            let html = Self.buildFullHTML(from: text, theme: theme, baseURL: baseURL)
            let blocks = includeBlocks ? MarkdownParser.shared.parse(text) : []
            DispatchQueue.main.async {
                if includeBlocks {
                    self?.applyParseResult(generation: generation, blocks: blocks, html: html)
                } else {
                    self?.applyHTMLResult(generation: generation, html: html)
                }
            }
        }
    }

    /// Этап 3: инкрементирует и возвращает новое поколение. Точка планирования
    /// (scheduleReparse) вызывает её перед уходом в фон; юнит-тест использует
    /// для честной эмуляции двух фоновых задач с разными поколениями.
    @discardableResult
    func advanceGeneration() -> Int {
        parseGeneration += 1
        return parseGeneration
    }

    /// Этап 3: применение результата фонового парсинга. internal — юнит-тест
    /// вызывает напрямую: устаревший generation не должен применяться.
    func applyParseResult(generation: Int, blocks: [MarkdownBlock], html: String) {
        guard generation == parseGeneration else { return }
        parsedBlocks = blocks
        renderedHTML = html
    }

    /// Этап 3: применение только HTML (смена темы). Тот же generation-guard.
    private func applyHTMLResult(generation: Int, html: String) {
        guard generation == parseGeneration else { return }
        renderedHTML = html
    }

    /// Этап 3: порог «большого» документа — байты ИЛИ строки.
    static func isLargeDocument(_ text: String) -> Bool {
        if text.utf8.count >= largeDocumentByteThreshold { return true }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
        return lines >= largeDocumentLineThreshold
    }

    /// Пересобирает renderedHTML с новым оформлением (R5). Вызывается из View-слоя
    /// при смене настроек темы/шрифта. Затрагивает только renderedHTML: не меняет
    /// text, не триггерит autosave и запись на диск.
    /// Этап 3: шлёт через общий generation-пайплайн — не по порядку завершённые
    /// фоновые сборки больше не затирают свежий HTML. Блоки не пересчитываются:
    /// text не менялся.
    func regenerateHTML(theme: HTMLTheme) {
        currentTheme = theme
        scheduleReparse(text: text, includeBlocks: false)
    }

    /// Собирает полный HTML-документ с CSS-стилизацией для WKWebView.
    /// Оформление передаётся параметром (R5): резолв настроек — в HTMLTheme.resolved().
    /// SPEC R-MD-9: baseURL (URL документа) пробрасывается в рендер для резолва картинок.
    /// Этап 2 (SPEC N-6): theme.allowRemoteImages управляет загрузкой http(s)-изображений.
    static func buildFullHTML(from source: String, theme: HTMLTheme, baseURL: URL?) -> String {
        let bodyHTML = MarkdownToHTML.convert(source, baseURL: baseURL, allowRemoteImages: theme.allowRemoteImages)
        let fontSize = theme.fontSize
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        * { box-sizing: border-box; }
        html, body {
            overflow-x: hidden !important;
            width: 100% !important;
            max-width: 100% !important;
            word-break: break-word !important;
            overflow-wrap: break-word !important;
            overscroll-behavior-x: none !important;
        }
        pre, code {
            white-space: pre-wrap !important;
            word-break: break-word !important;
            overflow-x: hidden !important;
        }
        table {
            max-width: 100% !important;
            width: 100% !important;
            table-layout: fixed !important;
            word-break: break-word !important;
        }
        th, td {
            word-break: break-word !important;
            overflow-wrap: break-word !important;
        }
        img, video, iframe, embed, object {
            max-width: 100% !important;
            height: auto !important;
        }
        /* Fallback-контраст (v0.6.4): читаемые текст/фон и видимые границы таблиц
           даже ДО применения темы и при пустом cssBody (.neutral). Тема ниже
           переопределяет эти значения (source order, равная специфичность). */
        :root { color-scheme: light dark; }
        @media (prefers-color-scheme: light) {
            body { color: #1d1d1f; background-color: #ffffff; }
            h1, h2, h3, h4, h5, h6 { color: #1d1d1f; }
            a { color: #0071e3; }
            code { color: #1d1d1f; background: #f5f5f7; }
            blockquote { color: #86868b; border-left: 3px solid #d2d2d7; }
        }
        table { border-collapse: collapse; }
        th, td { border: 1px solid rgba(128, 128, 128, 0.5); padding: 8px 14px; text-align: left; }
        th { background: rgba(128, 128, 128, 0.1); font-weight: 600; }
        @media (prefers-color-scheme: dark) {
            body { color: #f5f5f7; background-color: #1c1c1e; }
            h1, h2, h3, h4, h5, h6 { color: #f5f5f7; }
            a { color: #2997ff; }
            code { color: #f5f5f7; background: #2c2c2e; }
            blockquote { color: #98989d; border-left: 3px solid #48484a; }
            th, td { border-color: #48484a; }
            th { background: #2c2c2e; }
        }
        \(theme.cssBody)
        body { font-size: \(fontSize)px !important; }
        h1, h2, h3, h4, h5, h6 { line-height: 1.3; margin-top: 1.4em; margin-bottom: 0.6em; }
        p { margin: 0.8em 0; }
        ul, ol { padding-left: 1.8em; }
        li { margin: 0.3em 0; }
        img { max-width: 100%; border-radius: 8px; }
        /* GFM task list чекбоксы (SPEC R-MD-4): read-only, стилизованы под нативные */
        input.task-checkbox {
            accent-color: #007AFF;
            width: 14px;
            height: 14px;
            vertical-align: middle;
            margin-right: 4px;
        }
        /* Этап 2 (SPEC N-6): плейсхолдер заблокированного удалённого изображения */
        .blocked-image {
            display: inline-block;
            padding: 6px 12px;
            margin: 4px 0;
            border: 1px dashed rgba(128, 128, 128, 0.45);
            border-radius: 8px;
            background: rgba(128, 128, 128, 0.08);
            color: rgba(128, 128, 128, 1);
            font-size: 0.85em;
            user-select: none;
        }
        a { text-decoration: none; }
        a:hover { text-decoration: underline; }
        [data-source-line] {
            border-left: 3px solid transparent;
            padding-left: 6px;
            transition: background 0.15s ease, border-left-color 0.15s ease;
        }
        table[data-source-line] {
            border-left: none;
            padding-left: 0;
        }
        .highlight-active {
            background: rgba(59, 130, 246, 0.08);
            border-left-color: rgba(59, 130, 246, 0.6) !important;
            border-radius: 4px;
        }
        table.highlight-active {
            border-left: none !important;
            outline: 2px solid rgba(59, 130, 246, 0.6);
            border-radius: 4px;
        }
        /* Table WYSIWYG styles */
        .table-container {
            position: relative;
            margin: 20px 0;
            display: inline-block;
            max-width: 100%;
        }
        .table-container table {
            margin: 0 !important;
            border-collapse: collapse;
        }
        .table-action-btn {
            width: 20px;
            height: 20px;
            border-radius: 50%;
            border: 1px solid rgba(128, 128, 128, 0.3);
            background: rgba(255, 255, 255, 0.9);
            backdrop-filter: blur(8px);
            -webkit-backdrop-filter: blur(8px);
            color: #666;
            font-size: 14px;
            font-weight: 500;
            cursor: pointer;
            opacity: 0;
            transition: opacity 0.15s ease, background-color 0.15s ease, border-color 0.15s ease, color 0.15s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 0;
            line-height: 1;
            z-index: 10;
        }
        .table-container:hover .table-action-btn,
        .table-action-btn:hover {
            opacity: 1;
        }
        .table-action-btn:hover {
            background: rgba(0, 122, 255, 0.1);
            border-color: rgba(0, 122, 255, 0.4);
            color: #007AFF;
        }
        @media (prefers-color-scheme: dark) {
            .table-action-btn {
                background: rgba(60, 60, 60, 0.9);
                border-color: rgba(128, 128, 128, 0.4);
                color: #aaa;
            }
            .table-action-btn:hover {
                background: rgba(0, 122, 255, 0.15);
                color: #4da3ff;
            }
        }
        .table-container th, .table-container td {
            position: relative;
        }
        .table-del-col {
            position: absolute;
            top: -11px;
            left: 50%;
            transform: translateX(-50%);
        }
        .table-del-row {
            position: absolute;
            left: -11px;
            top: 50%;
            transform: translateY(-50%);
        }
        .table-add-row {
            position: absolute;
            bottom: -11px;
            left: 50%;
            transform: translateX(-50%);
        }
        .table-add-col {
            position: absolute;
            right: -11px;
            top: 50%;
            transform: translateY(-50%);
        }
        ::-webkit-scrollbar { width: 8px; }
        ::-webkit-scrollbar-track { background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgba(128,128,128,0.3); border-radius: 4px; }
        </style>
        </head>
        <body>\(HTMLTheme.bodyMarker)\(bodyHTML)</body>
        </html>
        """
    }

    // MARK: ReferenceFileDocument

    /// Этап 1: снимок — только чтение памяти, без диска. Сериализация записей
    /// (debounce + periodic) — в `DocumentFileService.ioQueue`; системный
    /// snapshot/fileWrapper не пишут напрямую, поэтому гонки писателей нет:
    /// последний писатель определяется порядком в `ioQueue`, отмена
    /// `autosaveWork` перед внешними изменениями — у владельца (ContentView).
    func snapshot(contentType: UTType) throws -> String {
        text
    }

    func fileWrapper(snapshot: String, configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(snapshot.utf8))
    }
}
