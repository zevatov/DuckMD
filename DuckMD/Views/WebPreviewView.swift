import SwiftUI
import WebKit

/// Рендерер Markdown через WKWebView.
/// Двусторонний скролл: принимает дробь от редактора И отдаёт свою при пользовательском скролле.
struct WebPreviewView: NSViewRepresentable {
    let htmlContent: String
    /// SPEC R-MD-9: URL файла документа. Если задан — превью грузится через
    /// `loadFileURL` (temp-копия HTML + read-доступ к папке документа), чтобы
    /// local file://-картинки (в т.ч. с резолвнутыми относительными путями)
    /// загружались. nil — прежний путь `loadHTMLString(baseURL: nil)`.
    var documentFileURL: URL? = nil
    /// Дробь скролла 0...1 от редактора. nil = не синхронизировать позицию.
    var scrollFraction: CGFloat? = nil
    /// Позиция скролла (строка, смещение 0...1, общая дробь 0...1) для умного центрированного скролла
    var scrollPosition: (line: Int, offset: CGFloat, fraction: CGFloat)? = nil
    /// Активная линия для синхронизации выделения (1-индексированная)
    var activeLine: Int = 1
    /// Активная колонка для выделения ячейки
    var activeCol: Int? = nil
    /// Callback: пользователь проскроллил превью (дробь 0...1)
    var onScroll: ((CGFloat) -> Void)? = nil
    /// Callback: пользователь проскроллил превью (активная строка по центру, следующая строка, смещение, общая дробь)
    var onScrollPosition: ((Int, Int?, CGFloat, CGFloat) -> Void)? = nil
    /// Конец пользовательского жеста превью (payload.ended). Не позиция.
    var onScrollGestureEnded: (() -> Void)? = nil
    /// Callback: клик по элементу в превью (передает номер строки)
    var onElementClicked: ((Int) -> Void)? = nil
    /// Callback: редактирование элемента в превью (номер строки, новый текст)
    var onElementEdited: ((Int, String) -> Void)? = nil
    /// Callback: редактирование ячейки таблицы (номер строки таблицы, ряд, колонка, новый текст)
    var onTableCellEdited: ((Int, Int, Int, String) -> Void)? = nil
    /// Callback: добавление строки в таблицу (номер строки таблицы)
    var onTableAddRow: ((Int) -> Void)? = nil
    /// Callback: добавление колонки в таблицу (номер строки таблицы)
    var onTableAddCol: ((Int) -> Void)? = nil
    /// Callback: удаление строки из таблицы (номер строки таблицы, индекс строки 1+)
    var onTableDelRow: ((Int, Int) -> Void)? = nil
    /// Callback: удаление колонки из таблицы (номер строки таблицы, индекс колонки 0+)
    var onTableDelCol: ((Int, Int) -> Void)? = nil
    /// Callback: toggle task-чекбокса (строка блока, новое состояние)
    var onCheckboxToggled: ((Int, Bool) -> Void)? = nil
    /// Флаг скрытия встроенного скроллбара (для сплит-режима с центральной рельсой)
    var hideScrollbar: Bool = false

    func makeCoordinator() -> Coordinator {
        let coord = Coordinator(onScroll: onScroll, onScrollPosition: onScrollPosition, onScrollGestureEnded: onScrollGestureEnded, onElementClicked: onElementClicked, onElementEdited: onElementEdited)
        coord.onTableCellEdited = onTableCellEdited
        coord.onTableAddRow = onTableAddRow
        coord.onTableAddCol = onTableAddCol
        coord.onTableDelRow = onTableDelRow
        coord.onTableDelCol = onTableDelCol
        coord.onCheckboxToggled = onCheckboxToggled
        return coord
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let userContentController = WKUserContentController()

        // R7: JS → Swift — регистрация всех хендлеров через слабые обёртки
        // (обёртки сохраняются в coordinator для снятия в dismantleNSView).
        context.coordinator.messageHandlerWrappers =
            PreviewMessageHandlerName.allCases.map { name in
                let wrapper = WeakScriptMessageHandler(context.coordinator)
                userContentController.add(wrapper, name: name.rawValue)
                return wrapper
            }

        // JS: слушает scroll, клики, и управляет подсветкой (R7: вынесен в PreviewBridgeScript)
        let scriptSource = PreviewBridgeScript.source
        let scrollScript = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        userContentController.addUserScript(scrollScript)
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        // Цвет подложки webView строго совпадает с выбранной темой (исключает белый флэш)
        let bgNSColor = SettingsStore.shared.renderTheme.nsBackgroundColor(for: SettingsStore.shared.theme)
        webView.underPageBackgroundColor = bgNSColor
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = false
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView

        // Фикс «пустой preview при открытии»: первичный HTML грузим всегда,
        // даже пустую строку — иначе свежий Coordinator (например, после
        // переключения режима) остаётся без навигации, а updateNSView решает,
        // что head «не изменился» (оба пусты), и live-обновлений не будет.
        context.coordinator.lastHTML = htmlContent
        // R7: head по шаблонному маркеру (fallback — substring-поиск).
        context.coordinator.lastHead = PreviewBridgeScript.headSection(from: htmlContent)
        context.coordinator.load(html: htmlContent, documentFileURL: documentFileURL, webView: webView)
        return webView
    }

    /// R7: снятие всех script message handlers при демонтаже view.
    /// WKUserContentController удерживает обёртки сильно — явное снятие разрывает
    /// удержание Coordinator (и его callbacks) после ухода representable.
    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        coordinator.messageHandlerWrappers = []
        // Этап 3: отменяем отложенную большую замену тела — таймер не должен
        // стрелять в демонтаже view.
        coordinator.cancelLargeBodyApply()
        coordinator.webView = nil
    }

    /// Идемпотентный updateNSView: не блокирует первичную загрузку (навигация,
    /// стартованная в makeNSView, никогда не перезапускается теми же данными),
    /// живые правки применяет через innerHTML, смену head — полной загрузкой.
    /// Этап 3: тела больше 200 КБ применяются с троттлингом (не чаще 1 раза
    /// в 175 мс) — гигантские строки больше не сериализуются в JSON на каждый кадр.
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.onScrollPosition = onScrollPosition
        context.coordinator.onScrollGestureEnded = onScrollGestureEnded
        context.coordinator.onElementClicked = onElementClicked
        context.coordinator.onElementEdited = onElementEdited
        context.coordinator.onTableCellEdited = onTableCellEdited
        context.coordinator.onTableAddRow = onTableAddRow
        context.coordinator.onTableAddCol = onTableAddCol
        context.coordinator.onTableDelRow = onTableDelRow
        context.coordinator.onTableDelCol = onTableDelCol
        context.coordinator.onCheckboxToggled = onCheckboxToggled

        let bgNSColor = SettingsStore.shared.renderTheme.nsBackgroundColor(for: SettingsStore.shared.theme)
        if webView.underPageBackgroundColor != bgNSColor {
            webView.underPageBackgroundColor = bgNSColor
        }

        let newHTML = htmlContent
        let coord = context.coordinator

        // R7: разбор по шаблонному маркеру `<!--DUCKMD:BODY-->` вместо substring-поиска.
        let headContent = PreviewBridgeScript.headSection(from: newHTML)
        let bodyContent = PreviewBridgeScript.bodySection(from: newHTML)

        var htmlDidChange = false

        if coord.lastHead != headContent {
            coord.lastHead = headContent
            coord.lastHTML = newHTML
            coord.load(html: newHTML, documentFileURL: documentFileURL, webView: webView)
            htmlDidChange = true
        } else if newHTML != coord.lastHTML {
            coord.lastHTML = newHTML
            htmlDidChange = true
            // Этап 3: маленькое тело — как раньше (немедленный innerHTML);
            // большое — через троттлинг (не чаще 1 раза / 175 мс), иначе каждый
            // кадр набора текста гонял JSON-сериализацию сотен килобайт.
            if bodyContent.utf8.count >= Coordinator.largeBodyByteThreshold {
                coord.enqueueLargeBodyApply(bodyContent, webView: webView)
            } else {
                coord.cancelLargeBodyApply()
                coord.applyBodyViaInnerHTML(bodyContent, restoreFraction: coord.lastAppliedFraction, webView: webView)
            }
        }

        // Синхронизация скролла от редактора (приоритет у точного центрированного scrollPosition)
        if let pos = scrollPosition {
            let inResize = webView.window?.inLiveResize ?? false
            let posChanged = coord.lastAppliedPosition?.line != pos.line ||
                             abs((coord.lastAppliedPosition?.offset ?? 0) - pos.offset) > 0.01 ||
                             abs((coord.lastAppliedPosition?.fraction ?? 0) - pos.fraction) > 0.001
            let fullReload = coord.isAwaitingNavigation
            if !inResize && (posChanged || (htmlDidChange && !fullReload)) {
                if fullReload {
                    coord.pendingScrollPosition = pos
                } else {
                    coord.lastAppliedPosition = pos
                    coord.lastAppliedFraction = pos.fraction
                    let js = "window.scrollToSourceLine(\(pos.line), \(pos.offset), \(pos.fraction));"
                    coord.evaluateScrollScript(js, in: webView)
                }
            }
        } else if let fraction = scrollFraction {
            let inResize = webView.window?.inLiveResize ?? false
            let fractionChanged = abs(coord.lastAppliedFraction - fraction) > 0.0001
            let fullReload = coord.isAwaitingNavigation
            if !inResize && (fractionChanged || (htmlDidChange && !fullReload)) {
                if fullReload {
                    coord.pendingScrollFraction = fraction
                } else {
                    coord.lastAppliedFraction = fraction
                    let js = "window.scrollToProgrammatic(\(fraction));"
                    coord.evaluateScrollScript(js, in: webView)
                }
            }
        }

        // Синхронизация активной строки от редактора — аналогично скроллу.
        let colArg = activeCol?.description ?? "null"
        if coord.lastAppliedActiveLine != activeLine || coord.lastAppliedActiveCol != activeCol || (htmlDidChange && !coord.isAwaitingNavigation) {
            if coord.isAwaitingNavigation {
                coord.pendingActiveLine = activeLine
                coord.pendingActiveCol = activeCol
            } else {
                coord.lastAppliedActiveLine = activeLine
                coord.lastAppliedActiveCol = activeCol
                let js = "window.highlightLine(\(activeLine), \(colArg));"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        // Управление видимостью нативного скроллбара
        webView.evaluateJavaScript("if (window.setScrollbarVisible) window.setScrollbarVisible(\(!hideScrollbar));", completionHandler: nil)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        /// Этап 3: порог тела, начиная с которого innerHTML-замены троттлятся.
        static let largeBodyByteThreshold = 200 * 1024
        /// Этап 3: минимальный интервал между большими innerHTML-заменами.
        static let largeBodyApplyInterval: TimeInterval = 0.175
        /// R7: ссылки на обёртки хендлеров для снятия в dismantleNSView.
        var messageHandlerWrappers: [WeakScriptMessageHandler] = []
        var onScroll: ((CGFloat) -> Void)?
        var onScrollPosition: ((Int, Int?, CGFloat, CGFloat) -> Void)?
        var onScrollGestureEnded: (() -> Void)?
        var onElementClicked: ((Int) -> Void)?
        var onElementEdited: ((Int, String) -> Void)?
        var onTableCellEdited: ((Int, Int, Int, String) -> Void)?
        var onTableAddRow: ((Int) -> Void)?
        var onTableAddCol: ((Int) -> Void)?
        var onTableDelRow: ((Int, Int) -> Void)?
        var onTableDelCol: ((Int, Int) -> Void)?
        var onCheckboxToggled: ((Int, Bool) -> Void)?
        
        var lastHTML: String = ""
        var lastHead: String = ""
        weak var webView: WKWebView?
        /// Этап 3: отложенное применение большого тела + таймер троттлинга.
        private var pendingLargeBody: String? = nil
        private var largeBodyApplyTimer: Timer? = nil
        private var lastLargeBodyApplyAt: TimeInterval = 0

        /// Этап 3: маленькие тела — немедленный innerHTML с восстановлением
        /// скролла. После замены ОБЯЗАТЕЛЬНО `_rebuildBlocksCache()` в том же
        /// JS: иначе кэш блоков остаётся по старым координатам и скролл-синк
        /// целится в несуществующую разметку.
        func applyBodyViaInnerHTML(_ body: String, restoreFraction fraction: CGFloat, webView: WKWebView) {
            guard let jsonBodyData = try? JSONSerialization.data(withJSONObject: [body], options: []),
                  let jsonBodyString = String(data: jsonBodyData, encoding: .utf8) else { return }
            let js = """
            (function() {
                if (document.hasFocus() && document.activeElement && document.activeElement.hasAttribute('contenteditable')) {
                    return;
                }
                var beforeY = window.scrollY || window.pageYOffset;
                _isProgrammatic = true;
                document.body.innerHTML = \(jsonBodyString)[0];
                var maxScroll = document.body.scrollHeight - window.innerHeight;
                var targetY = maxScroll > 0 ? \(fraction) * maxScroll : beforeY;
                if (maxScroll > 0) window.scrollTo(0, targetY);
                if (window._rebuildBlocksCache) window._rebuildBlocksCache();
                var afterY = window.scrollY || window.pageYOffset;
                if (afterY === beforeY || maxScroll <= 0) {
                    _isProgrammatic = false;
                }
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        /// Этап 3: большие тела — троттлинг. Первый вызов применяется сразу,
        /// последующие в пределах интервала — откладываются на таймер (или
        /// пропускаются, пока навигация не завершилась).
        func enqueueLargeBodyApply(_ body: String, webView: WKWebView) {
            guard !isAwaitingNavigation else {
                pendingLargeBody = body
                return
            }
            let now = Date().timeIntervalSinceReferenceDate
            let elapsed = now - lastLargeBodyApplyAt
            if elapsed >= Self.largeBodyApplyInterval {
                applyLargeBodyNow(body, webView: webView)
            } else {
                pendingLargeBody = body
                if largeBodyApplyTimer == nil {
                    largeBodyApplyTimer = Timer.scheduledTimer(withTimeInterval: Self.largeBodyApplyInterval - elapsed, repeats: false) { [weak self] _ in
                        guard let self else { return }
                        self.largeBodyApplyTimer = nil
                        if let body = self.pendingLargeBody, !self.isAwaitingNavigation {
                            self.pendingLargeBody = nil
                            self.applyLargeBodyNow(body, webView: webView)
                        }
                    }
                }
            }
        }

        private func applyLargeBodyNow(_ body: String, webView: WKWebView) {
            lastLargeBodyApplyAt = Date().timeIntervalSinceReferenceDate
            pendingLargeBody = nil
            applyBodyViaInnerHTML(body, restoreFraction: lastAppliedFraction, webView: webView)
        }

        /// Этап 3: отмена отложенного большого применения (при малом теле или
        /// демонтаже view) — не применяем устаревший контент позже.
        func cancelLargeBodyApply() {
            pendingLargeBody = nil
            largeBodyApplyTimer?.invalidate()
            largeBodyApplyTimer = nil
        }
        var lastAppliedFraction: CGFloat = 0
        var lastAppliedPosition: (line: Int, offset: CGFloat, fraction: CGFloat)? = nil
        var lastAppliedActiveLine: Int = 1
        var lastAppliedActiveCol: Int? = nil
        /// Дробь, отложенная на момент загрузки страницы: навигация асинхронна,
        /// и evaluateJavaScript из updateNSView выполняется до готовности DOM.
        /// didFinish применяет её после реального окончания навигации.
        var pendingScrollFraction: CGFloat? = nil
        var pendingScrollPosition: (line: Int, offset: CGFloat, fraction: CGFloat)? = nil
        /// Активная строка, отложенная до didFinish (та же причина).
        var pendingActiveLine: Int? = nil
        var pendingActiveCol: Int? = nil
        /// True между start Navigation (load) и didFinish — updateNSView в этот
        /// интервал не шлёт JS в неготовый DOM, а откладывает значения.
        var isAwaitingNavigation: Bool = false

        /// Coalescing для evaluateJavaScript при скролле: предотвращает насыщение шины IPC WebKit
        private var isEvaluatingScroll: Bool = false
        private var pendingScrollScript: String? = nil

        func evaluateScrollScript(_ js: String, in webView: WKWebView) {
            if isEvaluatingScroll {
                pendingScrollScript = js
                return
            }
            isEvaluatingScroll = true
            webView.evaluateJavaScript(js) { [weak self, weak webView] _, _ in
                guard let self = self else { return }
                self.isEvaluatingScroll = false
                if let nextJS = self.pendingScrollScript {
                    self.pendingScrollScript = nil
                    if let wv = webView ?? self.webView {
                        self.evaluateScrollScript(nextJS, in: wv)
                    }
                }
            }
        }

        init(onScroll: ((CGFloat) -> Void)?, onScrollPosition: ((Int, Int?, CGFloat, CGFloat) -> Void)? = nil, onScrollGestureEnded: (() -> Void)? = nil, onElementClicked: ((Int) -> Void)?, onElementEdited: ((Int, String) -> Void)?) {
            self.onScroll = onScroll
            self.onScrollPosition = onScrollPosition
            self.onScrollGestureEnded = onScrollGestureEnded
            self.onElementClicked = onElementClicked
            self.onElementEdited = onElementEdited
        }

        // MARK: WKNavigationDelegate — пост-загрузочная синхронизация

        /// Первичная загрузка стала надёжной: после didFinish DOM готов, bridge-скрипт
        /// исполнен — можно программно скроллить и подсвечивать без гонок.
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isAwaitingNavigation = false
            // Этап 3: большой body, отложенный на время навигации, применяем
            // сразу после готовности DOM (иначе правка терялась бы до первого
            // очередного кадра).
            if let body = pendingLargeBody, let wv = self.webView {
                pendingLargeBody = nil
                applyLargeBodyNow(body, webView: wv)
            }
            if let pos = pendingScrollPosition {
                pendingScrollPosition = nil
                lastAppliedPosition = pos
                webView.evaluateJavaScript("window.scrollToSourceLine(\(pos.line), \(pos.offset), \(pos.fraction));", completionHandler: nil)
            } else if let fraction = pendingScrollFraction {
                pendingScrollFraction = nil
                lastAppliedFraction = fraction
                webView.evaluateJavaScript("window.scrollToProgrammatic(\(fraction));", completionHandler: nil)
            }
            if let line = pendingActiveLine {
                pendingActiveLine = nil
                lastAppliedActiveLine = line
                let colArg = pendingActiveCol?.description ?? "null"
                pendingActiveCol = nil
                webView.evaluateJavaScript("window.highlightLine(\(line), \(colArg));", completionHandler: nil)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isAwaitingNavigation = false
            Diag.preview.error("WebPreview didFail: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            isAwaitingNavigation = false
            Diag.preview.error("WebPreview didFailProvisionalNavigation: \(error.localizedDescription)")
        }

        /// Политика навигации (Этап 2, SPEC N-6):
        /// - первичная загрузка (loadHTMLString) разрешена — определяем по признаку
        ///   isAwaitingNavigation, а НЕ безусловным allow для .other. Это покрывает
        ///   loadHTMLString с file:// baseURL (базовый каталог документа) и about:blank;
        /// - http/https — всегда в системный браузер (NSWorkspace.open) + cancel;
        /// - javascript:/file:/data: и неизвестные схемы — cancel + лог (scheme-only);
        /// - внутристраничные якоря (#) — разрешены.
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Первичная загрузка (интервал между load(...) и didFinish) — всегда allow:
            // loadHTMLString(baseURL: каталог документа) даёт file://-навигацию,
            // а при baseURL == nil — about:blank. isAwaitingNavigation сбрасывается
            // в didFinish/didFail, после чего клики/редиректы снова фильтруются.
            if isAwaitingNavigation {
                decisionHandler(.allow)
                return
            }
            guard let url = navigationAction.request.url else {
                // Внеполосный запрос без URL — не первичная загрузка, блокируем.
                decisionHandler(.cancel)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""

            // about:blank — первичная загрузка через loadHTMLString.
            if url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }

            // Якоря внутри страницы — разрешаем (навигация не уходит со страницы).
            if let fragment = url.fragment, !fragment.isEmpty, scheme.isEmpty || scheme == "file" || scheme == "about" {
                decisionHandler(.allow)
                return
            }

            // Внешние http/https — в системный браузер, в webview не грузим.
            if scheme == "http" || scheme == "https" {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }

            // javascript:/file:/data:/vbscript: и прочие схемы — блокируем.
            // scheme-only лог без query/path (SPEC N-6: URL может содержать PII).
            Diag.preview.info("Preview navigation blocked, scheme=\(scheme.isEmpty ? "none" : scheme, privacy: .public)")
            decisionHandler(.cancel)
        }

        // MARK: - Загрузка превью

        /// Загружает HTML через loadHTMLString с baseURL каталога документа.
        /// Исключает сбои песочницы WebKit (loadFileURL) и позволяет отображать локальные картинки.
        func load(html: String, documentFileURL: URL?, webView: WKWebView) {
            isAwaitingNavigation = true
            let baseDir = documentFileURL?.deletingLastPathComponent()
            webView.loadHTMLString(html, baseURL: baseDir)
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            // R7: имена — из PreviewMessageHandlerName, payload — Codable-структуры.
            if message.name == PreviewMessageHandlerName.scrollHandler.rawValue {
                if let payload = PreviewBridgeScript.decode(ScrollPositionPayload.self, from: message.body) {
                    let ended = payload.ended == true
                    DispatchQueue.main.async {
                        if ended {
                            self.onScrollGestureEnded?()
                        } else {
                            self.onScrollPosition?(payload.line, payload.nextLine, CGFloat(payload.offset), CGFloat(payload.fraction))
                            self.onScroll?(CGFloat(payload.fraction))
                        }
                    }
                } else if let dict = message.body as? [String: Any],
                          let fraction = dict["fraction"] as? Double {
                    let line = dict["line"] as? Int ?? 1
                    let nextLine = dict["nextLine"] as? Int
                    let offset = dict["offset"] as? Double ?? 0.0
                    let ended = (dict["ended"] as? Bool) == true
                    DispatchQueue.main.async {
                        if ended {
                            self.onScrollGestureEnded?()
                        } else {
                            self.onScrollPosition?(line, nextLine, CGFloat(offset), CGFloat(fraction))
                            self.onScroll?(CGFloat(fraction))
                        }
                    }
                } else if let fraction = message.body as? Double {
                    let cgFraction = CGFloat(fraction)
                    DispatchQueue.main.async {
                        self.onScrollPosition?(1, nil, 0, cgFraction)
                        self.onScroll?(cgFraction)
                    }
                }
            } else if message.name == PreviewMessageHandlerName.elementClickHandler.rawValue,
                      let line = message.body as? Int {
                DispatchQueue.main.async {
                    self.onElementClicked?(line)
                }
            } else if message.name == PreviewMessageHandlerName.editContentHandler.rawValue,
                      let payload = PreviewBridgeScript.decode(EditContentPayload.self, from: message.body) {
                DispatchQueue.main.async {
                    if let row = payload.row, let col = payload.col {
                        self.onTableCellEdited?(payload.line, row, col, payload.text)
                    } else {
                        self.onElementEdited?(payload.line, payload.text)
                    }
                }
            } else if message.name == PreviewMessageHandlerName.tableAddRowHandler.rawValue,
                      let payload = PreviewBridgeScript.decode(TableLinePayload.self, from: message.body) {
                DispatchQueue.main.async {
                    self.onTableAddRow?(payload.line)
                }
            } else if message.name == PreviewMessageHandlerName.tableAddColHandler.rawValue,
                      let payload = PreviewBridgeScript.decode(TableLinePayload.self, from: message.body) {
                DispatchQueue.main.async {
                    self.onTableAddCol?(payload.line)
                }
            } else if message.name == PreviewMessageHandlerName.tableDelRowHandler.rawValue,
                      let payload = PreviewBridgeScript.decode(TableDelRowPayload.self, from: message.body) {
                DispatchQueue.main.async {
                    self.onTableDelRow?(payload.line, payload.row)
                }
            } else if message.name == PreviewMessageHandlerName.tableDelColHandler.rawValue,
                      let payload = PreviewBridgeScript.decode(TableDelColPayload.self, from: message.body) {
                DispatchQueue.main.async {
                    self.onTableDelCol?(payload.line, payload.col)
                }
            } else if message.name == PreviewMessageHandlerName.checkboxToggleHandler.rawValue,
                      let payload = PreviewBridgeScript.decode(CheckboxTogglePayload.self, from: message.body) {
                DispatchQueue.main.async {
                    self.onCheckboxToggled?(payload.line, payload.checked)
                }
            }
        }
    }
}
