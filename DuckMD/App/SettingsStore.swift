import SwiftUI

/// Режимы оформления приложения
enum ThemeMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"
    
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Системная"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }
}

/// Дизайны шрифта для отображения разметки
enum FontDesignMode: String, CaseIterable, Identifiable {
    case serif = "serif"
    case sans = "sans"
    case mono = "mono"
    
    var id: String { rawValue }
    var label: String {
        switch self {
        case .serif: return "Засечки"
        case .sans: return "Без засечек"
        case .mono: return "Моноширинный"
        }
    }
    
    var design: Font.Design {
        switch self {
        case .serif: return .serif
        case .sans: return .default
        case .mono: return .monospaced
        }
    }
}

/// Темы рендерера — Apple-style, каждая с light и dark вариантами CSS.
enum RenderThemeOption: String, CaseIterable, Identifiable {
    case apple = "apple"
    case paper = "paper"
    case mono = "mono"
    case ocean = "ocean"
    case night = "night"
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
        case .apple:  return "Apple"
        case .paper:  return "Paper"
        case .mono:   return "Mono"
        case .ocean:  return "Ocean"
        case .night:  return "Night"
        }
    }
    
    var subtitle: String {
        switch self {
        case .apple:  return "Системный"
        case .paper:  return "Книжный"
        case .mono:   return "Моноширинный"
        case .ocean:  return "Голубой"
        case .night:  return "Ночной"
        }
    }

    // MARK: - Light CSS
    
    var cssLight: String {
        switch self {
        case .apple:
            return """
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif;
                background-color: #ffffff;
                color: #1d1d1f;
                line-height: 1.65;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #0071e3; text-decoration: none; }
            a:hover { text-decoration: underline; }
            code { background: rgba(0, 0, 0, 0.05); color: #1d1d1f; padding: 2.5px 6px; border-radius: 6px; font-family: 'SF Mono', ui-monospace, Menlo, monospace; font-size: 0.88em; }
            pre {
                background: #f6f8fa;
                border: 1px solid rgba(0, 0, 0, 0.06);
                padding: 16px 18px;
                border-radius: 10px;
                overflow-x: auto;
                box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
            }
            pre code { background: none; padding: 0; color: #24292f; }
            blockquote {
                border-left: 3.5px solid #0071e3;
                background: rgba(0, 113, 227, 0.04);
                margin-left: 0;
                padding: 10px 16px;
                border-radius: 0 8px 8px 0;
                color: #515154;
            }
            table { border-collapse: collapse; width: 100%; border-radius: 8px; overflow: hidden; }
            th, td { border: 1px solid rgba(0, 0, 0, 0.08); padding: 10px 14px; text-align: left; }
            th { background: rgba(0, 0, 0, 0.04); font-weight: 600; color: #1d1d1f; }
            h1, h2, h3, h4, h5, h6 { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif; color: #1d1d1f; font-weight: 700; }
            h1 { font-size: 2.1em; letter-spacing: -0.022em; margin-top: 1.2em; margin-bottom: 0.5em; }
            h2 { font-size: 1.55em; letter-spacing: -0.019em; margin-top: 1.1em; margin-bottom: 0.4em; }
            h3 { font-size: 1.25em; letter-spacing: -0.014em; margin-top: 1.0em; margin-bottom: 0.3em; }
            hr { border: none; height: 1px; background: rgba(0, 0, 0, 0.08); }
            img { border-radius: 10px; }
            """
        case .paper:
            return """
            body {
                font-family: 'New York', Georgia, 'Times New Roman', serif;
                background-color: #faf8f5;
                color: #2c2c2e;
                line-height: 1.75;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #8b6914; } a:hover { color: #a07d1c; }
            code { background: #f0ece4; padding: 2px 6px; border-radius: 4px; font-family: 'SF Mono', Menlo, monospace; font-size: 0.88em; }
            pre { background: #f0ece4; padding: 16px; border-radius: 8px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #c7b99a; margin-left: 0; padding-left: 16px; color: #7a7067; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #d8cfc0; padding: 8px 14px; text-align: left; }
            th { background: #f0ece4; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #1a1a1c; }
            hr { border: none; height: 1px; background: #d8cfc0; }
            """
        case .mono:
            return """
            body {
                font-family: 'SF Mono', ui-monospace, Menlo, 'Courier New', monospace;
                background-color: #ffffff;
                color: #1d1d1f;
                line-height: 1.6;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                font-size: 0.92em;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #0071e3; } a:hover { color: #0077ed; }
            code { background: #f5f5f7; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
            pre { background: #f5f5f7; padding: 16px; border-radius: 8px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #d2d2d7; margin-left: 0; padding-left: 16px; color: #86868b; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #d2d2d7; padding: 8px 14px; text-align: left; }
            th { background: #f5f5f7; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #1d1d1f; }
            hr { border: none; height: 1px; background: #d2d2d7; }
            """
        case .ocean:
            return """
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                background-color: #f0f6fc;
                color: #1b2a4a;
                line-height: 1.65;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #2563eb; } a:hover { color: #1d4ed8; }
            code { background: #dbeafe; color: #1e40af; padding: 2px 6px; border-radius: 5px; font-family: 'SF Mono', Menlo, monospace; font-size: 0.88em; }
            pre { background: #dbeafe; padding: 16px; border-radius: 10px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #93c5fd; margin-left: 0; padding-left: 16px; color: #3b6fa0; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #bfdbfe; padding: 8px 14px; text-align: left; }
            th { background: #dbeafe; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #0f1d3a; }
            hr { border: none; height: 1px; background: #bfdbfe; }
            """
        case .night:
            return """
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                background-color: #1c1c1e;
                color: #e5e5ea;
                line-height: 1.65;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #64d2ff; } a:hover { color: #5ac8fa; }
            code { background: #2c2c2e; color: #32d74b; padding: 2px 6px; border-radius: 5px; font-family: 'SF Mono', Menlo, monospace; font-size: 0.88em; }
            pre { background: #2c2c2e; padding: 16px; border-radius: 10px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #48484a; margin-left: 0; padding-left: 16px; color: #98989d; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #48484a; padding: 8px 14px; text-align: left; }
            th { background: #2c2c2e; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #ffffff; }
            hr { border: none; height: 1px; background: #48484a; }
            """
        }
    }
    
    // MARK: - Dark CSS
    
    var cssDark: String {
        switch self {
        case .apple:
            return """
            body {
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "SF Pro Display", "Helvetica Neue", sans-serif;
                background-color: #1c1c1e;
                color: #f5f5f7;
                line-height: 1.65;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #2997ff; text-decoration: none; }
            a:hover { text-decoration: underline; }
            code { background: rgba(255, 255, 255, 0.1); color: #f5f5f7; padding: 2.5px 6px; border-radius: 6px; font-family: 'SF Mono', ui-monospace, Menlo, monospace; font-size: 0.88em; }
            pre {
                background: #252528;
                border: 1px solid rgba(255, 255, 255, 0.08);
                padding: 16px 18px;
                border-radius: 10px;
                overflow-x: auto;
                box-shadow: 0 1px 3px rgba(0, 0, 0, 0.2);
            }
            pre code { background: none; padding: 0; color: #f5f5f7; }
            blockquote {
                border-left: 3.5px solid #2997ff;
                background: rgba(41, 151, 255, 0.06);
                margin-left: 0;
                padding: 10px 16px;
                border-radius: 0 8px 8px 0;
                color: #a1a1a6;
            }
            table { border-collapse: collapse; width: 100%; border-radius: 8px; overflow: hidden; }
            th, td { border: 1px solid rgba(255, 255, 255, 0.1); padding: 10px 14px; text-align: left; }
            th { background: rgba(255, 255, 255, 0.06); font-weight: 600; color: #f5f5f7; }
            h1, h2, h3, h4, h5, h6 { font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "SF Pro Text", sans-serif; color: #f5f5f7; font-weight: 700; }
            h1 { font-size: 2.1em; letter-spacing: -0.022em; margin-top: 1.2em; margin-bottom: 0.5em; }
            h2 { font-size: 1.55em; letter-spacing: -0.019em; margin-top: 1.1em; margin-bottom: 0.4em; }
            h3 { font-size: 1.25em; letter-spacing: -0.014em; margin-top: 1.0em; margin-bottom: 0.3em; }
            hr { border: none; height: 1px; background: rgba(255, 255, 255, 0.1); }
            img { border-radius: 10px; }
            """
        case .paper:
            return """
            body {
                font-family: 'New York', Georgia, 'Times New Roman', serif;
                background-color: #2c2c2e;
                color: #e5e5ea;
                line-height: 1.75;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #d4a935; } a:hover { color: #e0b840; }
            code { background: #3a3a3c; padding: 2px 6px; border-radius: 4px; font-family: 'SF Mono', Menlo, monospace; font-size: 0.88em; }
            pre { background: #3a3a3c; padding: 16px; border-radius: 8px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #636366; margin-left: 0; padding-left: 16px; color: #98989d; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #48484a; padding: 8px 14px; text-align: left; }
            th { background: #3a3a3c; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #f5f5f7; }
            hr { border: none; height: 1px; background: #48484a; }
            """
        case .mono:
            return """
            body {
                font-family: 'SF Mono', ui-monospace, Menlo, 'Courier New', monospace;
                background-color: #1c1c1e;
                color: #e5e5ea;
                line-height: 1.6;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                font-size: 0.92em;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #2997ff; } a:hover { color: #64d2ff; }
            code { background: #2c2c2e; padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
            pre { background: #2c2c2e; padding: 16px; border-radius: 8px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #48484a; margin-left: 0; padding-left: 16px; color: #98989d; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #48484a; padding: 8px 14px; text-align: left; }
            th { background: #2c2c2e; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #f5f5f7; }
            hr { border: none; height: 1px; background: #48484a; }
            """
        case .ocean:
            return """
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
                background-color: #0c1929;
                color: #c8d6e5;
                line-height: 1.65;
                max-width: 100%; margin: 0 auto; padding: 28px 32px;
                -webkit-font-smoothing: antialiased;
            }
            a { color: #60a5fa; } a:hover { color: #93bbfc; }
            code { background: #1e3a5f; color: #93c5fd; padding: 2px 6px; border-radius: 5px; font-family: 'SF Mono', Menlo, monospace; font-size: 0.88em; }
            pre { background: #1e3a5f; padding: 16px; border-radius: 10px; overflow-x: auto; }
            pre code { background: none; padding: 0; }
            blockquote { border-left: 3px solid #2563eb; margin-left: 0; padding-left: 16px; color: #7ba4d4; }
            table { border-collapse: collapse; width: 100%; }
            th, td { border: 1px solid #1e3a5f; padding: 8px 14px; text-align: left; }
            th { background: #1e3a5f; font-weight: 600; }
            h1, h2, h3, h4, h5, h6 { color: #e8f0fe; }
            hr { border: none; height: 1px; background: #1e3a5f; }
            """
        case .night:
            // Night is already dark, same CSS
            return cssLight
        }
    }

    /// CSS выбранного варианта оформления. Для явных light/dark вариант
    /// фиксируется на Swift-стороне: `@media (prefers-color-scheme)` внутри
    /// WKWebView с прозрачным фоном (drawsBackground=false) давал
    /// неконтрастный светлый режим, когда appearance webview расходился с
    /// выбранной темой приложения. light → белый фон/тёмный текст всегда,
    /// dark → тёмный вариант всегда. system → прежнее поведение: медиа-блок
    /// с автопереключением внутри webview.
    func cssBody(for mode: ThemeMode) -> String {
        switch mode {
        case .light: return cssLight
        case .dark: return cssDark
        case .system:
            return """
            @media (prefers-color-scheme: light) {
            \(cssLight)
            }
            @media (prefers-color-scheme: dark) {
            \(cssDark)
            }
            """
        }
    }
    
    // MARK: - Preview Colors (Light)
    
    var previewLightBg: Color {
        switch self {
        case .apple:  return Color(white: 1.0)
        case .paper:  return Color(red: 0.98, green: 0.97, blue: 0.96)
        case .mono:   return Color(white: 1.0)
        case .ocean:  return Color(red: 0.94, green: 0.96, blue: 0.99)
        case .night:  return Color(red: 0.11, green: 0.11, blue: 0.12)
        }
    }
    
    var previewLightFg: Color {
        switch self {
        case .apple:  return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .paper:  return Color(red: 0.17, green: 0.17, blue: 0.18)
        case .mono:   return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .ocean:  return Color(red: 0.11, green: 0.16, blue: 0.29)
        case .night:  return Color(red: 0.90, green: 0.90, blue: 0.92)
        }
    }
    
    var previewLightAccent: Color {
        switch self {
        case .apple:  return Color(red: 0.0, green: 0.44, blue: 0.89)
        case .paper:  return Color(red: 0.55, green: 0.41, blue: 0.08)
        case .mono:   return Color(red: 0.0, green: 0.44, blue: 0.89)
        case .ocean:  return Color(red: 0.15, green: 0.39, blue: 0.92)
        case .night:  return Color(red: 0.39, green: 0.82, blue: 1.0)
        }
    }

    // MARK: - Preview Colors (Dark)
    
    var previewDarkBg: Color {
        switch self {
        case .apple:  return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .paper:  return Color(red: 0.17, green: 0.17, blue: 0.18)
        case .mono:   return Color(red: 0.11, green: 0.11, blue: 0.12)
        case .ocean:  return Color(red: 0.05, green: 0.10, blue: 0.16)
        case .night:  return Color(red: 0.11, green: 0.11, blue: 0.12)
        }
    }
    
    var previewDarkFg: Color {
        switch self {
        case .apple:  return Color(red: 0.96, green: 0.96, blue: 0.97)
        case .paper:  return Color(red: 0.90, green: 0.90, blue: 0.92)
        case .mono:   return Color(red: 0.90, green: 0.90, blue: 0.92)
        case .ocean:  return Color(red: 0.78, green: 0.84, blue: 0.90)
        case .night:  return Color(red: 0.90, green: 0.90, blue: 0.92)
        }
    }
    
    var previewDarkAccent: Color {
        switch self {
        case .apple:  return Color(red: 0.16, green: 0.59, blue: 1.0)
        case .paper:  return Color(red: 0.83, green: 0.66, blue: 0.21)
        case .mono:   return Color(red: 0.16, green: 0.59, blue: 1.0)
        case .ocean:  return Color(red: 0.38, green: 0.65, blue: 0.98)
        case .night:  return Color(red: 0.39, green: 0.82, blue: 1.0)
        }
    }

    // MARK: - Native NSColor for WKWebView Underpage Background

    func nsBackgroundColor(for mode: ThemeMode) -> NSColor {
        let isDark: Bool
        switch mode {
        case .light: isDark = false
        case .dark: isDark = true
        case .system:
            isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        }
        switch self {
        case .apple:
            return isDark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) : .white
        case .paper:
            return isDark ? NSColor(srgbRed: 0.17, green: 0.17, blue: 0.18, alpha: 1.0) : NSColor(srgbRed: 0.98, green: 0.97, blue: 0.96, alpha: 1.0)
        case .mono:
            return isDark ? NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0) : .white
        case .ocean:
            return isDark ? NSColor(srgbRed: 0.05, green: 0.10, blue: 0.16, alpha: 1.0) : NSColor(srgbRed: 0.94, green: 0.96, blue: 0.99, alpha: 1.0)
        case .night:
            return NSColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1.0)
        }
    }
}

/// Хранилище настроек приложения с использованием @AppStorage
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    
    // MARK: - Внешний вид
    
    @AppStorage("theme") var theme: ThemeMode = .system {
        didSet { applyTheme() }
    }
    @AppStorage("readingWidth") var readingWidth: Double = 720
    @AppStorage("bodyFontDesign") var bodyFontDesign: FontDesignMode = .serif
    @AppStorage("renderTheme") var renderTheme: RenderThemeOption = .apple
    @AppStorage("renderFontSize") var renderFontSize: Double = 16
    
    // MARK: - Редактор
    
    @AppStorage("autoformatEnabled") var autoformatEnabled: Bool = true
    @AppStorage("autoClosePairs") var autoClosePairs: Bool = true
    @AppStorage("editorFontSize") var editorFontSize: Double = 13
    @AppStorage("syncScroll") var syncScroll: Bool = true
    @AppStorage("showLineNumbers") var showLineNumbers: Bool = true
    
    // MARK: - Файлы
    
    @AppStorage("autosaveEnabled") var autosaveEnabled: Bool = true
    @AppStorage("maxRecentFiles") var maxRecentFiles: Int = 50
    /// Секунды до авто-принятия внешних изменений (баннер FileWatcher), R9.
    @AppStorage("extChangeTimerSeconds") var extChangeTimerSeconds: Int = 5
    @AppStorage("autoSaveInterval") var autoSaveInterval: Double = 300
    @AppStorage("periodicAutosaveEnabled") var periodicAutosaveEnabled: Bool = true
    @AppStorage("defaultSavePath") var defaultSavePath: String = ""
    
    // MARK: - Приватность превью (Этап 2, SPEC N-6)
    
    /// Загрузка удалённых (http/https) изображений в превью. По умолчанию OFF:
    /// WKWebView не должен тянуть трекинг-пиксели при открытии документа.
    @AppStorage("allowRemoteImages") var allowRemoteImages: Bool = false
    
    // MARK: - Окно
    
    @AppStorage("windowWidth") var windowWidth: Double = 1000
    @AppStorage("windowHeight") var windowHeight: Double = 700
    
    private var appearanceObservation: NSKeyValueObservation?
    
    private init() {
        setupDefaultSavePath()
        applyTheme()
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            guard let self = self else { return }
            AppIconHelper.updateDockIcon(forTheme: self.theme)
        }
    }
    
    /// Этап 2 (SPEC N-7): безопасный дефолт-путь сохранения БЕЗ force-unwrap.
    /// Заданная пользователем папка → иначе ~/Documents/DuckMD;
    /// documentDirectory недоступен → nil (вызывающий код решает сам).
    func defaultSaveFolderURL() -> URL? {
        if !defaultSavePath.isEmpty {
            return URL(fileURLWithPath: defaultSavePath)
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("DuckMD", isDirectory: true)
    }
    
    private func setupDefaultSavePath() {
        let fileManager = FileManager.default
        if let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
            let defaultURL = documentsURL.appendingPathComponent("DuckMD", isDirectory: true)
            if !fileManager.fileExists(atPath: defaultURL.path) {
                try? fileManager.createDirectory(at: defaultURL, withIntermediateDirectories: true)
            }
            if defaultSavePath.isEmpty {
                defaultSavePath = defaultURL.path
            }
        }
    }
    
    /// Применить тему оформления к окнам приложения
    func applyTheme() {
        DispatchQueue.main.async {
            switch self.theme {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
            AppIconHelper.updateDockIcon(forTheme: self.theme)
        }
    }
}
