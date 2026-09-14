import XCTest
@testable import DuckMD

/// Регресс-тесты v0.6.4 (пустой preview при открытии, чёрный текст на чёрном,
/// невидимые границы таблиц, scroll-синхронизация после первичной загрузки).
final class PreviewContrastAndScrollTests: XCTestCase {

    // MARK: - Fallback-контраст в buildFullHTML

    /// Явные text/background в шаблоне: не полагаемся на прозрачный webview
    /// или неявный system appearance. Раньше отсутствие гарантированного
    /// цвета давало чёрный текст на чёрном фоне при гонке CSS.
    func testBuildFullHTMLHasExplicitContrastFallback() {
        let html = MarkdownDocument.buildFullHTML(from: "# T", theme: .neutral, baseURL: nil)
        XCTAssertTrue(html.contains("body { color: #1d1d1f; background-color: #ffffff; }"),
                      "fallback: тёмный текст на белом в light")
        XCTAssertTrue(html.contains("color: #f5f5f7; background-color: #1c1c1e;"),
                      "fallback: светлый текст на тёмном в dark")
    }

    /// Границы таблиц видны даже без темы (проблема «не видны границы таблиц»).
    func testBuildFullHTMLHasTableBorderFallback() {
        let src = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = MarkdownDocument.buildFullHTML(from: src, theme: .neutral, baseURL: nil)
        XCTAssertTrue(html.contains("th, td { border: 1px solid"),
                      "fallback: ячейки таблицы обязаны иметь границу")
        XCTAssertTrue(html.contains("border-collapse: collapse"),
                      "таблица — collapse для корректных границ")
    }

    /// Fallback для dark не применён насильно: тема light должна перебить
    /// dark-fallback (source order: fallback идёт раньше cssBody темы).
    func testLightThemeOverridesDarkFallback() {
        let theme = HTMLTheme(
            cssBody: RenderThemeOption.apple.cssBody(for: .light),
            fontSize: 16)
        let html = MarkdownDocument.buildFullHTML(from: "# T", theme: theme, baseURL: nil)
        // Порядок: fallback light → fallback dark (@media) → cssBody light.
        // Ищем ПОСЛЕДНЕЕ вхождение #ffffff: первое — сам fallback-light,
        // последнее — cssBody темы, идущий после dark-fallback и побеждающий.
        let fallbackDark = html.range(of: "color: #f5f5f7; background-color: #1c1c1e;")
        var themeRange: Range<String.Index>? = nil
        var searchStart = html.startIndex
        while let found = html.range(of: "background-color: #ffffff", range: searchStart..<html.endIndex) {
            themeRange = found
            searchStart = found.upperBound
        }
        XCTAssertNotNil(fallbackDark)
        XCTAssertNotNil(themeRange)
        if let f = fallbackDark, let t = themeRange {
            XCTAssertLessThan(f.lowerBound, t.lowerBound,
                              "light-CSS темы должен идти после dark-fallback и побеждать")
        }
    }

    /// color-scheme даёт webview подсказку для нативных элементов (скроллбар,
    /// чекбоксы) в обоих режимах.
    func testBuildFullHTMLDeclaresColorScheme() {
        let html = MarkdownDocument.buildFullHTML(from: "# T", theme: .neutral, baseURL: nil)
        XCTAssertTrue(html.contains("color-scheme: light dark"))
    }

    // MARK: - Шаблонные маркеры (контракт updateNSView)

    /// updateNSView сравнивает head-часть: маркер обязан присутствовать в
    /// шаблоне, иначе head/body-парсинг уходит в fallback и ломает innerHTML.
    func testTemplatePreservesBodyMarkerForHeadComparison() {
        let html = MarkdownDocument.buildFullHTML(from: "# T", theme: .neutral, baseURL: nil)
        let head = PreviewBridgeScript.headSection(from: html)
        let body = PreviewBridgeScript.bodySection(from: html)
        XCTAssertTrue(head.contains("<style>"), "head обязан нести стили")
        XCTAssertFalse(head.contains(HTMLTheme.bodyMarker))
        XCTAssertTrue(body.contains("<h1"), "body обязан нести контент")
        // Идемпотентность: тот же HTML → тот же head (дедуп обновлений).
        let html2 = MarkdownDocument.buildFullHTML(from: "# T", theme: .neutral, baseURL: nil)
        XCTAssertEqual(head, PreviewBridgeScript.headSection(from: html2))
    }

    /// Смена ТОЛЬКО body не должна менять head (live-обновление через innerHTML,
    /// без полной перезагрузки), смена темы — должна (head содержит CSS).
    func testHeadComparisonSemantics() {
        let base = MarkdownDocument.buildFullHTML(from: "# A", theme: .neutral, baseURL: nil)
        let editedBody = MarkdownDocument.buildFullHTML(from: "# A\n\nНовый абзац", theme: .neutral, baseURL: nil)
        let themed = MarkdownDocument.buildFullHTML(from: "# A", theme: HTMLTheme(cssBody: "body { background-color: #faf8f5; }", fontSize: 16), baseURL: nil)

        XCTAssertEqual(PreviewBridgeScript.headSection(from: base),
                       PreviewBridgeScript.headSection(from: editedBody),
                       "правка body не меняет head → innerHTML-ветка")
        XCTAssertNotEqual(PreviewBridgeScript.headSection(from: base),
                          PreviewBridgeScript.headSection(from: themed),
                          "смена темы меняет head → полная перезагрузка")
    }

    // MARK: - Контракт моста скролла

    /// scrollToProgrammatic и highlightLine обязаны существовать в bridge:
    /// didFinish вызывает их после загрузки (pending-очередь).
    func testBridgeScriptExposesScrollAndHighlightAPI() {
        XCTAssertTrue(PreviewBridgeScript.source.contains("window.scrollToProgrammatic = function"))
        XCTAssertTrue(PreviewBridgeScript.source.contains("window.highlightLine = function"))
        // Защита от echo: программный скролл не ретранслируется обратно.
        XCTAssertTrue(PreviewBridgeScript.source.contains("_isProgrammatic"),
                      "флаг _isProgrammatic обязателен против feedback loop")
    }

    /// Первичный рендер даже для пустой строки непуст как шаблон: head со
    /// стилями есть → webview грузит контрастную страницу, не «пустоту».
    func testEmptyDocumentStillProducesStyledShell() {
        let html = MarkdownDocument.buildFullHTML(from: "", theme: .neutral, baseURL: nil)
        XCTAssertTrue(html.contains("<style>"))
        XCTAssertTrue(html.contains("background-color: #ffffff"))
        XCTAssertTrue(html.contains(HTMLTheme.bodyMarker))
    }

    // MARK: - Smart Sync Scroll & Typography Tests (v0.6.6)

    /// Проверяет наличие scrollToSourceLine в bridge script для центрированного скролла.
    func testBridgeScriptExposesScrollToSourceLineAPI() {
        XCTAssertTrue(PreviewBridgeScript.source.contains("window.scrollToSourceLine = function"),
                      "Bridge script обязан содержать функцию scrollToSourceLine")
        XCTAssertTrue(PreviewBridgeScript.source.contains("window.scrollTo(0, 0)"),
                      "Должна быть поддержка доводки до верхнего края")
        XCTAssertTrue(PreviewBridgeScript.source.contains("data-source-line"),
                      "Должен быть поиск по data-source-line")
    }

    /// Проверяет декодирование payload скролла ScrollPositionPayload из словаря
    func testScrollPositionPayloadDecoding() {
        let dict: [String: Any] = [
            "line": 42,
            "nextLine": 55,
            "offset": 0.35,
            "fraction": 0.42
        ]
        let payload = PreviewBridgeScript.decode(ScrollPositionPayload.self, from: dict)
        XCTAssertNotNil(payload)
        XCTAssertEqual(payload?.line, 42)
        XCTAssertEqual(payload?.nextLine, 55)
        XCTAssertEqual(payload?.offset ?? 0, 0.35, accuracy: 0.001)
        XCTAssertEqual(payload?.fraction ?? 0, 0.42, accuracy: 0.001)

        // Без nextLine (nil)
        let dictWithoutNext: [String: Any] = [
            "line": 10,
            "offset": 0.1,
            "fraction": 0.05
        ]
        let payload2 = PreviewBridgeScript.decode(ScrollPositionPayload.self, from: dictWithoutNext)
        XCTAssertNotNil(payload2)
        XCTAssertEqual(payload2?.line, 10)
        XCTAssertNil(payload2?.nextLine)
    }

    /// Проверяет, что все темы возвращают валидный NSColor для фона webview
    func testRenderThemeNSBackgroundColor() {
        for theme in RenderThemeOption.allCases {
            let lightBg = theme.nsBackgroundColor(for: .light)
            let darkBg = theme.nsBackgroundColor(for: .dark)
            let systemBg = theme.nsBackgroundColor(for: .system)
            XCTAssertNotNil(lightBg)
            XCTAssertNotNil(darkBg)
            XCTAssertNotNil(systemBg)
        }
    }

    /// Проверяет наличие нативной типографики Apple и стилизации блоков кода
    func testAppleThemeTypographyCSS() {
        let lightCSS = RenderThemeOption.apple.cssBody(for: .light)
        let darkCSS = RenderThemeOption.apple.cssBody(for: .dark)
        XCTAssertTrue(lightCSS.contains("SF Pro Text") || lightCSS.contains("SF Pro Display"))
        XCTAssertTrue(lightCSS.contains("SF Mono"))
        XCTAssertTrue(lightCSS.contains("line-height: 1.65"))
        XCTAssertTrue(darkCSS.contains("background-color: #1c1c1e"))
    }

    // MARK: - Regress Tests v0.6.7 (Horizontal Lock, Continuous Scroll Sync, Converter)

    /// LockedHorizontalClipView обязан всегда принудительно фиксировать origin.x на базовой линии
    /// (0 без линейки или -ruleThickness с активной линейкой номеров строк), блокируя боковой сдвиг текста
    func testLockedHorizontalClipViewConstrainsXToZero() {
        let clipView = LockedHorizontalClipView()
        let docView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 1000))
        clipView.documentView = docView
        let proposed = NSRect(x: 42.5, y: 150.0, width: 300.0, height: 500.0)
        let constrained = clipView.constrainBoundsRect(proposed)
        XCTAssertEqual(constrained.origin.x, 0.0, "origin.x обязан быть 0 без линейки для исключения горизонтального сдвига текста")
        XCTAssertEqual(constrained.origin.y, 150.0, "origin.y сохраняется для вертикального скролла")

        // С включенной линейкой номеров строк (rulersVisible = true)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 500, height: 400))
        let rulerClipView = LockedHorizontalClipView()
        scrollView.contentView = rulerClipView
        let docViewWithRuler = NSView(frame: NSRect(x: 0, y: 0, width: 464, height: 2000))
        scrollView.documentView = docViewWithRuler
        let ruler = NSRulerView(scrollView: scrollView, orientation: .verticalRuler)
        ruler.ruleThickness = 36
        scrollView.hasVerticalRuler = true
        scrollView.verticalRulerView = ruler
        scrollView.rulersVisible = true
        scrollView.tile()

        let rulerProposed = NSRect(x: 50.0, y: 200.0, width: 464.0, height: 400.0)
        let rulerConstrained = rulerClipView.constrainBoundsRect(rulerProposed)
        XCTAssertEqual(rulerConstrained.origin.x, -36.0, "origin.x обязан блокироваться на -ruleThickness при видимой линейке")
        XCTAssertEqual(rulerConstrained.origin.y, 200.0, "origin.y сохраняется для вертикального скролла")
    }

    /// Bridge script обязан использовать непрерывный поиск блоков (targetBlock / nextBlock)
    /// без слепого сброса в line = 1 при прохождении межблочных зазоров
    func testBridgeScriptContinuousBlockTracking() {
        XCTAssertTrue(PreviewBridgeScript.source.contains("targetBlock"), "Скрипт должен отслеживать targetBlock")
        XCTAssertTrue(PreviewBridgeScript.source.contains("nextBlock"), "Скрипт должен отслеживать nextBlock для плавной интерполяции")
        XCTAssertTrue(PreviewBridgeScript.source.contains("totalDistance"), "Скрипт должен плавно интерполировать расстояние между блоками")
    }
}
