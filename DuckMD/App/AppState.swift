import SwiftUI
import Combine

/// Глобальное состояние приложения (режимы, настройки), расшаренное между окнами.
final class AppState: ObservableObject {
    /// Предпочтительная тема оформления (по умолчанию — за системой).
    @Published var prefersDark: Bool? = nil

    /// Ширина колонки чтения в пунктах.
    var readingWidth: CGFloat {
        CGFloat(SettingsStore.shared.readingWidth)
    }

    /// Текущий режим редактора.
    @Published var editorMode: EditorMode = .rendered

    /// Коэффициент разделения split-режима (доля кода слева, 0...1).
    @Published var splitRatio: CGFloat = 0.5

    /// Текущий открытый документ для редактирования
    @Published var activeDocument: MarkdownDocument? = nil

    /// G-2: файловый I/O открытия — через DocumentFileService (без SwiftUI-зависимостей).
    private let fileService = DocumentFileService()
    
    /// URL текущего открытого файла
    @Published var activeFileURL: URL? = nil
    
    /// Отображать ли Хаб в данный момент в единственном окне
    @Published var showHub: Bool = true

    /// URL файла, ожидающего конвертации
    @Published var pendingConversionURL: URL? = nil

    /// Ссылка на системное действие открытия окон
    var openWindowAction: OpenWindowAction?

    private var cancellables = Set<AnyCancellable>()

    init() {
        SettingsStore.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Мгновенный холодный старт: если файл передан через Finder/CLI до первого кадра
        if let url = AppDelegate.shared?.consumePendingURL() {
            if let text = try? fileService.readDocumentText(at: url) {
                let doc = MarkdownDocument(text: text, theme: .resolved(), documentURL: url)
                self.activeDocument = doc
                self.activeFileURL = url
                self.showHub = false
                RecentFilesStore.shared.addOrUpdate(url: url, title: url.deletingPathExtension().lastPathComponent, content: text)
            }
        }
    }

    /// Метод для открытия окна Хаба
    func openHub() {
        if Thread.isMainThread {
            self.showHub = true
        } else {
            DispatchQueue.main.async {
                self.showHub = true
            }
        }
    }

    /// Метод для открытия документа по URL
    ///
    /// Этап 5 (контракт security-scoped доступа): БЕЗ песочницы (D-25) этот метод
    /// всегда вызывается для пути, доступного напрямую; вызывающий, который открыл
    /// security-scoped доступ через bookmark (`HubView.openRecentFile`), обязан
    /// держать `startAccessingSecurityScopedResource()` живым на всё время
    /// синхронного чтения здесь и освободить его (`stop...`) сразу после возврата —
    /// далее документ живёт обычным path-I/O (вотчер/автосейв используют тот же
    /// путь без scope). Метод сам НЕ начинает и НЕ останавливает scoped-доступ.
    func openDocument(at url: URL) {
        do {
            // G-2: чтение через DocumentFileService (раньше — прямой Data(contentsOf:)).
            // Синхронно на вызывающем потоке: security-scoped доступ вызывающего
            // (HubView.openRecentFile) освобождается сразу после возврата (см.
            // контракт выше) — пока чтение идёт, доступ вызывающего ещё активен.
            let text = try fileService.readDocumentText(at: url)
            // R5: тема резолвится в App-слое — модель не знает о SettingsStore.
            // SPEC R-MD-9: URL передаётся в init — относительные пути картинок
            // резолвятся уже в синхронном первичном рендере.
            let doc = MarkdownDocument(text: text, theme: .resolved(), documentURL: url)

            let applyState = {
                self.activeDocument = doc
                self.activeFileURL = url
                self.showHub = false
                
                // Добавляем в недавние файлы
                RecentFilesStore.shared.addOrUpdate(url: url, title: url.deletingPathExtension().lastPathComponent, content: text)
            }

            if Thread.isMainThread {
                applyState()
            } else {
                DispatchQueue.main.async(execute: applyState)
            }
            // G-DIAG: событие открытия; путь приватный, размер — публичная метрика.
            Diag.app.info("Документ открыт, ext=\(Diag.ext(url), privacy: .public), bytes=\(text.utf8.count, privacy: .public)")
        } catch {
            // G-DIAG: путь и описание ошибки приватные; тип ошибки публичный.
            Diag.app.error("Ошибка открытия документа: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), path=\(url.path, privacy: .private)")
        }
    }

    var activeDocumentWordCountLabel: String {
        guard let text = activeDocument?.text else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let readingMin = max(1, Int(Double(words.count) / 200.0))
        return "\(words.count) слов · ~\(readingMin) мин чтения"
    }

    /// Метод для создания нового документа на диске (по типу Apple Notes)
    func createNewDocument() {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folderURL = documentsURL.appendingPathComponent("DuckMD", isDirectory: true)
        
        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        
        var targetURL = folderURL.appendingPathComponent("Без названия.md")
        var counter = 1
        while fileManager.fileExists(atPath: targetURL.path) {
            targetURL = folderURL.appendingPathComponent("Без названия \(counter).md")
            counter += 1
        }
        
        let initialContent = ""
        do {
            try initialContent.write(to: targetURL, atomically: true, encoding: .utf8)
            openDocument(at: targetURL)
            DispatchQueue.main.async {
                self.editorMode = .split
            }
            Diag.app.info("Новый документ создан")
        } catch {
            Diag.app.error("Ошибка создания документа: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private)")
        }
    }
}

/// Режим отображения документа.
enum EditorMode: String, CaseIterable, Identifiable {
    case rendered   // только красивый просмотр
    case split      // код + предпросмотр рядом (живая связь)
    case code       // только код

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rendered: return "Просмотр"
        case .split: return "Правка"
        case .code: return "Код"
        }
    }

    var systemImage: String {
        switch self {
        case .rendered: return "doc.richtext"
        case .split: return "rectangle.split.2x1"
        case .code: return "chevron.left.forwardslash.chevron.right"
        }
    }

    var keyboardHint: String {
        switch self {
        case .rendered: return "Просмотр (⌘1)"
        case .split: return "Правка: код + предпросмотр (⌘2)"
        case .code: return "Код (⌘3)"
        }
    }
}
