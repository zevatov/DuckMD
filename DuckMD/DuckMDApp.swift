import SwiftUI

@main
struct DuckMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Единственное главное окно приложения
        Window("DuckMD", id: "main") {
            MainContainerView()
                .environmentObject(appState)
                .onAppear {
                    appState.openWindowAction = openWindow
                    AppDelegate.shared.appState = appState
                    AppDelegate.shared.flushPendingOpenURL()
                }
                .onOpenURL { url in
                    appState.openDocument(at: url)
                }
                .frame(minWidth: 620, minHeight: 400)
        }
        .windowResizability(.contentSize)
        .windowToolbarStyle(.unified(showsTitle: false))
        .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
        .defaultSize(width: 960, height: 640)
        .commands {
            // О программе
            CommandGroup(replacing: .appInfo) {
                Button("О DuckMD") {
                    openWindow(id: "about")
                }
            }

            // Новое окно / документ
            CommandGroup(replacing: .newItem) {
                Button("Новый документ") {
                    appState.createNewDocument()
                }.keyboardShortcut("n", modifiers: .command)
                
                Button("Открыть документ...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.markdownDoc, .markdownStandard, .plainText]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.openDocument(at: url)
                    }
                }.keyboardShortcut("o", modifiers: .command)

                Divider()

                // R-DOC-4: копирование всего текста документа в clipboard.
                // Дублирует кнопку «Копировать текст» в тулбаре ContentView,
                // но доступно из меню в любом режиме и без фокуса на окне редактора.
                Button("Копировать текст") {
                    if let text = appState.activeDocument?.text {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(appState.activeDocument == nil)

            }

            // Переключение режимов Просмотр / Код
            CommandMenu("Вид") {
                Button("Просмотр") {
                    appState.editorMode = .rendered
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Правка") {
                    appState.editorMode = .split
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("Код") {
                    appState.editorMode = .code
                }
                .keyboardShortcut("3", modifiers: .command)

                Divider()

                Button("Светлая тема") {
                    SettingsStore.shared.theme = .light
                }.keyboardShortcut("l", modifiers: [.command, .control])

                Button("Тёмная тема") {
                    SettingsStore.shared.theme = .dark
                }.keyboardShortcut("d", modifiers: [.command, .control])

                Button("Системная тема") {
                    SettingsStore.shared.theme = .system
                }.keyboardShortcut("s", modifiers: [.command, .control])
            }
        }

        // Окно "О программе"
        Window("О DuckMD", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)

        // Окно "Конвертер"
        Window("Конвертер документов в MD", id: "converter") {
            ConverterView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)

        // Настройки приложения
        Settings {
            SettingsView()
        }
    }
}

/// Делегат приложения для тонкой настройки запуска и переоткрытия Хаба
class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    var appState: AppState?

    /// Файл, пришедший от Finder до готовности appState (холодный старт по
    /// двойному клику: openFiles-событие может прийти раньше onAppear главного
    /// окна). Флашится в flushPendingOpenURL() после привязки appState.
    private var pendingOpenURL: URL?

    override init() {
        super.init()
        AppDelegate.shared = self
        // Отключаем стандартный Finder диалог на старте
        UserDefaults.standard.set(false, forKey: "NSShowAppCentricOpenPanelInsteadOfUntitledFile")

        // Проверяем аргументы командной строки на наличие файла при прямом запуске
        for arg in CommandLine.arguments.dropFirst() {
            if !arg.hasPrefix("-") {
                let url = URL(fileURLWithPath: arg)
                if FileManager.default.fileExists(atPath: url.path) &&
                    (url.pathExtension == "md" || url.pathExtension == "markdown" || url.pathExtension == "txt") {
                    self.pendingOpenURL = url
                    break
                }
            }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if self.pendingOpenURL != nil || self.appState?.activeDocument != nil {
            return false
        }
        // Если нет отложенного открытия файла и нет активного документа — открываем Хаб
        DispatchQueue.main.async {
            if self.pendingOpenURL == nil && self.appState?.activeDocument == nil {
                self.appState?.showHub = true
            }
        }
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // При клике на иконку в доке, если окна нет, показываем его
        if let mainWindow = NSApp.windows.first(where: { $0.title == "DuckMD" && $0.identifier?.rawValue == "main" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        // Переходим в Хаб только если в данный момент нет активного открытого документа
        DispatchQueue.main.async {
            if self.appState?.activeDocument == nil {
                self.appState?.showHub = true
            }
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        openIncoming(url: url)
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        guard let filename = filenames.first else { return }
        openIncoming(url: URL(fileURLWithPath: filename))
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        openIncoming(url: URL(fileURLWithPath: filename))
        return true
    }

    private func openIncoming(url: URL) {
        if let appState = self.appState {
            if Thread.isMainThread {
                appState.openDocument(at: url)
            } else {
                DispatchQueue.main.async {
                    appState.openDocument(at: url)
                }
            }
        } else {
            self.pendingOpenURL = url
        }
    }

    /// Извлекает отложенный URL файла при холодном старте
    func consumePendingURL() -> URL? {
        let url = pendingOpenURL
        pendingOpenURL = nil
        return url
    }

    /// Применяет файл, отложенный при холодном старте (см. application(_:openFiles:)).
    func flushPendingOpenURL() {
        guard let url = pendingOpenURL else { return }
        pendingOpenURL = nil
        appState?.openDocument(at: url)
    }
}

/// Корневой контейнер приложения, управляющий переключением между Хабом и Редактором
struct MainContainerView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            if appState.showHub {
                HubView()
                    .transition(.opacity)
            } else if let document = appState.activeDocument {
                ContentView(document: document, fileURL: appState.activeFileURL)
                    .transition(.opacity)
            } else {
                HubView()
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .animation(.easeInOut(duration: 0.18), value: appState.showHub)
    }
}
