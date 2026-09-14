import AppKit
import WebKit

/// Надёжный экспорт PDF через WKNavigationDelegate (ожидает полную загрузку DOM).
/// R6: перенесён из ContentView.swift как есть (вместе с leak-фиксом Этапа 1 —
/// массив `active` + release()).
/// Этап 3: таймаут 15с — зависший didFinish больше не держит WKWebView в
/// `active` вечно; baseURL каталога документа — локальные картинки в PDF
/// больше не пропадают молча (resolveImage Этапа 2 уже вырезал http при
/// allowRemoteImages == false, поэтому file://-картинки безопасны).
final class PDFExporter: NSObject, WKNavigationDelegate {
    private let saveURL: URL
    private var webView: WKWebView?
    /// Удерживаем экземпляры в памяти до завершения экспорта.
    /// Коллекция (а не единственная ссылка): параллельные экспорты
    /// не затирают друг друга, каждый освобождается своим completion'ом.
    private static var active: [PDFExporter] = []
    /// Этап 3: верхняя граница ожидания загрузки HTML.
    private static let loadTimeout: TimeInterval = 15
    /// Этап 3: главный поток занят runModal — таймаут и release планируются на main.
    private var timeoutTimer: Timer? = nil

    private init(saveURL: URL) {
        self.saveURL = saveURL
    }

    static func export(html: String, to url: URL, baseURL: URL? = nil) {
        let exporter = PDFExporter(saveURL: url)
        active.append(exporter)
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        wv.navigationDelegate = exporter
        exporter.webView = wv
        // Этап 3: сторожевой таймер на main — если didFinish/didFail не пришли,
        // освобождаем webview (иначе экземпляр с webview висел вечно).
        let timer = Timer.scheduledTimer(withTimeInterval: Self.loadTimeout, repeats: false) { [weak exporter] _ in
            guard let exporter else { return }
            Diag.export.error("PDF экспорт: таймаут \(Self.loadTimeout, privacy: .public)с — didFinish не пришёл, webview освобождён")
            exporter.release()
        }
        exporter.timeoutTimer = timer
        let baseDir = baseURL?.deletingLastPathComponent()
        wv.loadHTMLString(html, baseURL: baseDir)
    }

    /// Гарантированное освобождение экземпляра (вызывается на всех ветках завершения).
    /// Этап 3: сторожевой таймер инвалидируется — после успеха/ошибки он не должен
    /// логировать ложный таймаут.
    private func release() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        webView?.navigationDelegate = nil
        webView = nil
        Self.active.removeAll { $0 === self }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let url = self.saveURL
        webView.createPDF(configuration: WKPDFConfiguration()) { [weak self] result in
            switch result {
            case .success(let data):
                do {
                    try data.write(to: url)
                    Diag.export.info("PDF экспортирован, bytes=\(data.count, privacy: .public)")
                } catch {
                    Diag.export.error("Ошибка записи PDF: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), path=\(url.path, privacy: .private)")
                }
            case .failure(let error):
                Diag.export.error("Ошибка генерации PDF: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private)")
            }
            self?.release()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Diag.export.error("Ошибка загрузки HTML для PDF: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private)")
        release()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Diag.export.error("Ошибка начальной загрузки HTML для PDF: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private)")
        release()
    }
}
