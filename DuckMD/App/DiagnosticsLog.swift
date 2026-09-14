import Foundation
import os

/// G-DIAG: диагностический слой поверх Unified Logging (os.Logger).
/// Только локальная диагностика: без сети, без телеметрии, без записи в файлы.
///
/// Privacy-модель:
/// - `.public` — безопасные локальные метаданные: счётчики, длительности,
///   типы ошибок/кодов, булевы флаги, расширения файлов, ID сессии.
/// - `.private` — пути файлов, имена файлов, человекочитаемые описания ошибок
///   (могут содержать имя файла). Видны только через `log show` на машине
///   пользователя, НЕ выгружаются автоматически и маскируются в Console.app.
/// - Запрещено логировать: содержимое документов, тексты, секреты, персональные данные.
///
/// Сбор: системный unified log (subsystem `net.duckmd.DuckMD`). Ротация —
/// на стороне системы (ASL/logd), собственного файла нет. Экспорт за период —
/// `scripts/export-diagnostics.sh`.
enum Diag {
    static let subsystem = "net.duckmd.DuckMD"

    /// Категория app: открытие/создание документов (lifecycle/хаб-события не логируются).
    static let app = Logger(subsystem: subsystem, category: "app")
    /// Категория file: ручное сохранение, rename, ошибки файлового I/O (autosave не логируется).
    static let file = Logger(subsystem: subsystem, category: "file")
    /// Категория watcher: наблюдение внешних изменений файла.
    static let watcher = Logger(subsystem: subsystem, category: "watcher")
    /// Категория preview: рендер/загрузка WKWebView-превью.
    static let preview = Logger(subsystem: subsystem, category: "preview")
    /// Категория export: PDF/конвертация/сохранение результатов.
    static let export = Logger(subsystem: subsystem, category: "export")

    // MARK: - Безопасные хелперы (privacy-политика в одном месте)

    /// Расширение файла — безопасные метаданные, можно публично.
    /// (Пути и размеры передаются в вызовах Logger напрямую с privacy-спецификаторами:
    /// `\(url.path, privacy: .private)`, `\(count, privacy: .public)`.)
    static func ext(_ url: URL) -> String {
        url.pathExtension.lowercased()
    }
}
