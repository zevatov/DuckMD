import Foundation
import WebKit

// MARK: - Message Handler Names (R7, P1-8)

/// Имена message-хендлеров JS → Swift. Контракт с [WebPreviewView.swift] и
/// скролл-синком: менять rawValue запрещено — JS-сторона шлёт ровно эти строки.
enum PreviewMessageHandlerName: String, CaseIterable {
    /// Пользователь проскроллил превью (payload: Double — дробь 0...1).
    case scrollHandler
    /// Клик по элементу (payload: Int — номер строки).
    case elementClickHandler
    /// Редактирование элемента/ячейки таблицы (payload: EditContentPayload).
    case editContentHandler
    /// Добавление строки таблицы (payload: TableLinePayload).
    case tableAddRowHandler
    /// Добавление колонки таблицы (payload: TableLinePayload).
    case tableAddColHandler
    /// Удаление строки таблицы (payload: TableDelRowPayload).
    case tableDelRowHandler
    /// Удаление колонки таблицы (payload: TableDelColPayload).
    case tableDelColHandler
    /// Toggle GFM task-чекбокса (payload: CheckboxTogglePayload).
    case checkboxToggleHandler
}

// MARK: - Payload Structures (R7, P2-14)

/// Редактирование элемента или ячейки таблицы (editContentHandler).
/// row/col присутствуют только для TD/TH.
struct EditContentPayload: Codable {
    let line: Int
    let text: String
    let row: Int?
    let col: Int?
}

/// Добавление строки/колонки таблицы (tableAddRowHandler / tableAddColHandler).
struct TableLinePayload: Codable {
    let line: Int
}

/// Удаление строки таблицы (tableDelRowHandler).
struct TableDelRowPayload: Codable {
    let line: Int
    let row: Int
}

/// Удаление колонки таблицы (tableDelColHandler).
struct TableDelColPayload: Codable {
    let line: Int
    let col: Int
}

/// Toggle GFM task-чекбокса (checkboxToggleHandler): line — data-source-line
/// родительского блока (параграф пункта списка), checked — новое состояние.
struct CheckboxTogglePayload: Codable {
    let line: Int
    let checked: Bool
}

/// Данные позиции скролла для центрированного синхронного скролла
struct ScrollPositionPayload: Codable {
    let line: Int
    let nextLine: Int?
    let offset: Double
    let fraction: Double
}

// MARK: - Bridge Script

/// JS-бридж превью (R7): единый источник JS-кода, регистрация/снятие хендлеров
/// и разбор HTML по шаблонному маркеру вместо substring-поиска.
enum PreviewBridgeScript {
    /// JS: программный скролл с защитой от echo, подсветка активной строки,
    /// слушатели input/click/scroll. Контекст контракта — PreviewMessageHandlerName.
    static let source: String = """
        var _isProgrammatic = false;
        var _programmaticTimer = null;
        var _blocksCache = [];
        function _rebuildBlocksCache() {
            var all = document.querySelectorAll('[data-source-line]');
            var currentScrollY = window.scrollY || window.pageYOffset;
            var map = new Map();
            for (var i = 0; i < all.length; i++) {
                var el = all[i];
                if (el.tagName === 'BUTTON' || el.classList.contains('table-action-btn')) continue;
                var l = parseInt(el.getAttribute('data-source-line'), 10);
                if (isNaN(l)) continue;

                // Пропускаем дочерние элементы с тем же номером строки, если есть родитель с той же строкой
                var parentWithLine = el.parentElement ? el.parentElement.closest('[data-source-line]') : null;
                if (parentWithLine) {
                    var pLine = parseInt(parentWithLine.getAttribute('data-source-line'), 10);
                    if (pLine === l) continue;
                }

                var rect = el.getBoundingClientRect();
                if (rect.height <= 0 && rect.width <= 0) continue;

                var blockObj = {
                    line: l,
                    top: rect.top + currentScrollY,
                    height: rect.height
                };

                // Сохраняем более крупный корневой блок для строки
                if (!map.has(l) || map.get(l).height < blockObj.height) {
                    map.set(l, blockObj);
                }
            }
            var list = Array.from(map.values());
            list.sort(function(a, b) { return a.line - b.line; });
            _blocksCache = list;
        }

        function _findBlockByLine(line) {
            if (!_blocksCache || _blocksCache.length === 0) return null;
            var low = 0, high = _blocksCache.length - 1;
            var best = 0;
            while (low <= high) {
                var mid = (low + high) >> 1;
                if (_blocksCache[mid].line <= line) {
                    best = mid;
                    low = mid + 1;
                } else {
                    high = mid - 1;
                }
            }
            return {
                target: _blocksCache[best],
                next: (best + 1 < _blocksCache.length) ? _blocksCache[best + 1] : null
            };
        }

        function _findBlockByScroll(centerY) {
            if (!_blocksCache || _blocksCache.length === 0) return null;
            var low = 0, high = _blocksCache.length - 1;
            var best = 0;
            while (low <= high) {
                var mid = (low + high) >> 1;
                if (_blocksCache[mid].top <= centerY) {
                    best = mid;
                    low = mid + 1;
                } else {
                    high = mid - 1;
                }
            }
            return {
                target: _blocksCache[best],
                next: (best + 1 < _blocksCache.length) ? _blocksCache[best + 1] : null
            };
        }

        window.addEventListener('resize', _rebuildBlocksCache);
        window.addEventListener('load', _rebuildBlocksCache);
        setTimeout(_rebuildBlocksCache, 150);

        window.setScrollbarVisible = function(visible) {
            if (visible) {
                document.body.classList.remove('hide-scrollbar');
            } else {
                document.body.classList.add('hide-scrollbar');
            }
        };

        var _hideScrollbarStyle = document.createElement('style');
        _hideScrollbarStyle.innerHTML = 'body.hide-scrollbar::-webkit-scrollbar { display: none !important; width: 0 !important; } body.hide-scrollbar { scrollbar-width: none !important; }';
        document.head.appendChild(_hideScrollbarStyle);

        // Вызывается из Swift — центрированный скролл по строке и смещению
        window.scrollToSourceLine = function(line, offsetInLine, fraction) {
            var maxScroll = document.body.scrollHeight - window.innerHeight;
            if (maxScroll <= 0) return;

            // Граничные положения: жесткая доводка до краев
            if (fraction !== null && fraction !== undefined) {
                if (fraction <= 0.005) {
                    _isProgrammatic = true;
                    if (_programmaticTimer) clearTimeout(_programmaticTimer);
                    window.scrollTo(0, 0);
                    _programmaticTimer = setTimeout(function() { _isProgrammatic = false; }, 40);
                    return;
                }
                if (fraction >= 0.995) {
                    _isProgrammatic = true;
                    if (_programmaticTimer) clearTimeout(_programmaticTimer);
                    window.scrollTo(0, maxScroll);
                    _programmaticTimer = setTimeout(function() { _isProgrammatic = false; }, 40);
                    return;
                }
            }

            if (_blocksCache.length === 0) {
                _rebuildBlocksCache();
            }

            var pair = _findBlockByLine(line);
            var targetBlock = pair ? pair.target : null;
            var nextBlock = pair ? pair.next : null;

            if (targetBlock) {
                var targetY = 0;
                if (nextBlock && nextBlock !== targetBlock && nextBlock.line > targetBlock.line) {
                    var lineSpan = Math.max(1, nextBlock.line - targetBlock.line);
                    var lineProgress = Math.max(0, Math.min((line - targetBlock.line + (offsetInLine || 0)) / lineSpan, 1));
                    targetY = (targetBlock.top + (nextBlock.top - targetBlock.top) * lineProgress) - (window.innerHeight / 2);
                } else {
                    targetY = (targetBlock.top + targetBlock.height * (offsetInLine || 0)) - (window.innerHeight / 2);
                }

                targetY = Math.max(0, Math.min(targetY, maxScroll));
                _isProgrammatic = true;
                if (_programmaticTimer) clearTimeout(_programmaticTimer);
                window.scrollTo(0, targetY);
                _programmaticTimer = setTimeout(function() { _isProgrammatic = false; }, 150);
            } else if (fraction !== null && fraction !== undefined) {
                _isProgrammatic = true;
                if (_programmaticTimer) clearTimeout(_programmaticTimer);
                window.scrollTo(0, fraction * maxScroll);
                _programmaticTimer = setTimeout(function() { _isProgrammatic = false; }, 150);
            }
        };

        // Вызывается из Swift — программный скролл с защитой от echo
        window.scrollToProgrammatic = function(fraction) {
            var maxScroll = document.body.scrollHeight - window.innerHeight;
            if (maxScroll <= 0) return;
            _isProgrammatic = true;
            if (_programmaticTimer) clearTimeout(_programmaticTimer);
            window.scrollTo(0, fraction * maxScroll);
            _programmaticTimer = setTimeout(function() {
                _isProgrammatic = false;
            }, 80);
        };

        // Вызывается из Swift — подсвечивает элемент по строке с дебаунсом
        window.highlightLine = function(line, col) {
            if (_highlightTimer) clearTimeout(_highlightTimer);
            _highlightTimer = setTimeout(function() {
                var elements = document.querySelectorAll('.highlight-active');
                for (var i = 0; i < elements.length; i++) {
                    elements[i].classList.remove('highlight-active');
                }
                if (!line) return;

                if (col !== null && col !== undefined) {
                    var rowTarget = document.querySelector('tr[data-source-line="' + line + '"]');
                    if (rowTarget) {
                        var cellIndex = col;
                        if (cellIndex >= 0 && cellIndex < rowTarget.cells.length) {
                            rowTarget.cells[cellIndex].classList.add('highlight-active');
                            return;
                        }
                    }
                }

                var target = document.querySelector('[data-source-line="' + line + '"]');
                if (target) {
                    target.classList.add('highlight-active');
                }
            }, 150);
        };

        // Слушаем ввод в редактируемых элементах
        document.addEventListener('input', function(event) {
            var target = event.target;
            if (target.hasAttribute('contenteditable')) {
                var block = target.closest('[data-source-line]');
                if (block) {
                    var line = parseInt(block.getAttribute('data-source-line'), 10);
                    if (!isNaN(line)) {
                        var cellText = target.innerText;
                        var textSpan = target.querySelector('.cell-text');
                        if (textSpan) {
                            cellText = textSpan.innerText;
                        } else if (target.querySelector('.table-action-btn')) {
                            var clone = target.cloneNode(true);
                            var btn = clone.querySelector('.table-action-btn');
                            if (btn) btn.remove();
                            cellText = clone.innerText;
                        }
                        var payload = {
                            line: line,
                            text: cellText
                        };
                        if (target.tagName === 'TD' || target.tagName === 'TH') {
                            var row = parseInt(target.getAttribute('data-row'), 10);
                            var col = parseInt(target.getAttribute('data-col'), 10);
                            if (!isNaN(row) && !isNaN(col)) {
                                payload.row = row;
                                payload.col = col;
                            }
                        }
                        window.webkit.messageHandlers.\(PreviewMessageHandlerName.editContentHandler.rawValue).postMessage(payload);
                    }
                }
            }
        });

        // Слушаем клики по элементам для синхронизации курсора и кнопок таблиц
        document.addEventListener('click', function(event) {
            var target = event.target;

            if (target.classList.contains('table-action-btn')) {
                var block = target.closest('[data-source-line]');
                if (block) {
                    var line = parseInt(block.getAttribute('data-source-line'), 10);
                    if (!isNaN(line)) {
                        if (target.classList.contains('table-add-row')) {
                            window.webkit.messageHandlers.\(PreviewMessageHandlerName.tableAddRowHandler.rawValue).postMessage({ line: line });
                        } else if (target.classList.contains('table-add-col')) {
                            window.webkit.messageHandlers.\(PreviewMessageHandlerName.tableAddColHandler.rawValue).postMessage({ line: line });
                        } else if (target.classList.contains('table-del-row')) {
                            var row = parseInt(target.getAttribute('data-row'), 10);
                            window.webkit.messageHandlers.\(PreviewMessageHandlerName.tableDelRowHandler.rawValue).postMessage({ line: line, row: row });
                        } else if (target.classList.contains('table-del-col')) {
                            var col = parseInt(target.getAttribute('data-col'), 10);
                            window.webkit.messageHandlers.\(PreviewMessageHandlerName.tableDelColHandler.rawValue).postMessage({ line: line, col: col });
                        }
                    }
                }
                event.stopPropagation();
                event.preventDefault();
                return;
            }

            var block = target.closest('[data-source-line]');
            if (block) {
                var line = parseInt(block.getAttribute('data-source-line'), 10);
                if (!isNaN(line)) {
                    window.webkit.messageHandlers.\(PreviewMessageHandlerName.elementClickHandler.rawValue).postMessage(line);
                }
            }
        });

        // Toggle GFM task-чекбоксов: change на .task-checkbox → payload {line, checked}.
        // line — data-source-line ближайшего блока (параграф пункта списка).
        document.addEventListener('change', function(event) {
            var target = event.target;
            if (target.classList && target.classList.contains('task-checkbox')) {
                var block = target.closest('[data-source-line]');
                if (block) {
                    var line = parseInt(block.getAttribute('data-source-line'), 10);
                    if (!isNaN(line)) {
                        window.webkit.messageHandlers.\(PreviewMessageHandlerName.checkboxToggleHandler.rawValue).postMessage({ line: line, checked: target.checked });
                    }
                }
            }
        });

        // Слушаем пользовательский скролл через requestAnimationFrame (синхронно с дисплеем)
        var _rafPending = false;
        window.addEventListener('scroll', function() {
            if (_isProgrammatic) return;
            if (_rafPending) return;
            _rafPending = true;
            requestAnimationFrame(function() {
                _rafPending = false;
                var maxScroll = document.body.scrollHeight - window.innerHeight;
                if (maxScroll <= 0) return;
                var scrollY = window.scrollY || window.pageYOffset;
                var fraction = scrollY / maxScroll;
                var roundedFraction = Math.round(fraction * 10000) / 10000;

                // Верхняя граница (жесткая доводка)
                if (scrollY <= 4) {
                    _lastFraction = 0;
                    window.webkit.messageHandlers.\(PreviewMessageHandlerName.scrollHandler.rawValue).postMessage({
                        line: 1,
                        offset: 0,
                        fraction: 0
                    });
                    return;
                }

                // Нижняя граница (жесткая доводка)
                if (scrollY >= maxScroll - 4) {
                    _lastFraction = 1;
                    window.webkit.messageHandlers.\(PreviewMessageHandlerName.scrollHandler.rawValue).postMessage({
                        line: 999999,
                        offset: 1,
                        fraction: 1
                    });
                    return;
                }

                if (_blocksCache.length === 0) {
                    _rebuildBlocksCache();
                }

                var centerY = scrollY + (window.innerHeight / 2);
                var pair = _findBlockByScroll(centerY);
                var targetBlock = pair ? pair.target : null;
                var nextBlock = pair ? pair.next : null;

                var line = 1;
                var offset = 0;
                if (targetBlock) {
                    line = targetBlock.line;
                    if (nextBlock && nextBlock !== targetBlock && nextBlock.top > targetBlock.top) {
                        var totalDistance = Math.max(1, nextBlock.top - targetBlock.top);
                        offset = (centerY - targetBlock.top) / totalDistance;
                    } else {
                        offset = (centerY - targetBlock.top) / Math.max(1, targetBlock.height);
                    }
                    offset = Math.max(0, Math.min(offset, 1));
                }

                _lastFraction = roundedFraction;
                var nextLineNum = (nextBlock && nextBlock !== targetBlock) ? nextBlock.line : null;
                window.webkit.messageHandlers.\(PreviewMessageHandlerName.scrollHandler.rawValue).postMessage({
                    line: line,
                    nextLine: (nextLineNum && !isNaN(nextLineNum)) ? nextLineNum : null,
                    offset: Math.round(offset * 1000) / 1000,
                    fraction: roundedFraction
                });
            });
        });

        // Блур активного элемента при потере фокуса окном webview
        window.addEventListener('blur', function() {
            if (document.activeElement) {
                document.activeElement.blur();
            }
        });
        """

    // MARK: Регистрация хендлеров

    /// Регистрирует все хендлеры через слабые обёртки: WKUserContentController
    /// держит обёртку, а не Coordinator — разрыв удержания после dismantle.
    static func registerHandlers(in controller: WKUserContentController,
                                 target: WKScriptMessageHandler) {
        for name in PreviewMessageHandlerName.allCases {
            controller.add(WeakScriptMessageHandler(target), name: name.rawValue)
        }
    }

    /// Снимает все зарегистрированные хендлеры (вызывается из dismantleNSView).
    static func removeHandlers(from controller: WKUserContentController) {
        for name in PreviewMessageHandlerName.allCases {
            controller.removeScriptMessageHandler(forName: name.rawValue)
        }
    }

    // MARK: Разбор HTML по шаблонному маркеру

    /// Head-часть документа: всё до `HTMLTheme.bodyMarker`. Fallback — старый
    /// substring-поиск `<head>...</head>` (для HTML вне шаблона модели).
    static func headSection(from html: String) -> String {
        let marker = HTMLTheme.bodyMarker
        if let markerRange = html.range(of: marker) {
            return String(html[html.startIndex..<markerRange.lowerBound])
        }
        if let start = html.range(of: "<head>"), let end = html.range(of: "</head>") {
            return String(html[start.lowerBound..<end.upperBound])
        }
        return ""
    }

    /// Body-контент: всё после `HTMLTheme.bodyMarker` до `</body>`. Fallback —
    /// старый substring-поиск; при отсутствии разметки — весь HTML как есть.
    static func bodySection(from html: String) -> String {
        let marker = HTMLTheme.bodyMarker
        if let markerRange = html.range(of: marker) {
            let bodyEnd = html.range(of: "</body>")?.lowerBound ?? html.endIndex
            return String(html[markerRange.upperBound..<bodyEnd])
        }
        if let start = html.range(of: "<body>")?.upperBound,
           let end = html.range(of: "</body>")?.lowerBound {
            return String(html[start..<end])
        }
        return html
    }

    // MARK: Декодирование payload

    /// Декодирует Codable-payload из тела WKScriptMessage (словарь из JS).
    static func decode<T: Decodable>(_ type: T.Type, from messageBody: Any) -> T? {
        guard let dictionary = messageBody as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [])
        else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Weak Wrapper

/// Слабая обёртка: WKUserContentController.add удерживает handler сильно;
/// обёртка не удерживает Coordinator → нет утечки после dismantleNSView.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
