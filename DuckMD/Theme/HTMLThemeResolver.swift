import Foundation

/// Плоский снимок оформления HTML-превью (R5, P0-3 из аудита).
/// MarkdownDocument не знает о SettingsStore — получает готовый параметр.
struct HTMLTheme: Equatable {
    /// Явный маркер шаблона buildFullHTML: head-часть до него, body — после
    /// (R7: вместо substring-поиска <head>/<body>).
    static let bodyMarker = "<!--DUCKMD:BODY-->"

    /// CSS темы (авто light/dark через @media).
    var cssBody: String
    /// Базовый размер шрифта превью в пунктах.
    var fontSize: Int
    /// Этап 2 (SPEC N-6): разрешена ли загрузка удалённых (http/https) изображений.
    /// По умолчанию OFF — снимок настроек пробрасывается в MarkdownToHTML.
    var allowRemoteImages: Bool

    /// Memberwise init с default (сохраняет компактные вызовы в тестах).
    init(cssBody: String, fontSize: Int, allowRemoteImages: Bool = false) {
        self.cssBody = cssBody
        self.fontSize = fontSize
        self.allowRemoteImages = allowRemoteImages
    }

    /// Нейтральное оформление по умолчанию (стартовое состояние до резолва из View-слоя).
    static let neutral = HTMLTheme(cssBody: "", fontSize: 16, allowRemoteImages: false)

    /// Собирает снимок из текущих настроек приложения.
    /// Вызывается только из View/App-слоя — Models остаётся независимым.
    /// Вариант light/dark CSS фиксируется по выбранной теме приложения
    /// (SettingsStore.theme), а не по @media внутри webview — см. cssBody(for:).
    static func resolved() -> HTMLTheme {
        HTMLTheme(
            cssBody: SettingsStore.shared.renderTheme.cssBody(for: SettingsStore.shared.theme),
            fontSize: Int(SettingsStore.shared.renderFontSize),
            allowRemoteImages: SettingsStore.shared.allowRemoteImages
        )
    }
}
