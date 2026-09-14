import Foundation

/// Этап 1: явные ошибки файлового I/O вместо молчаливых fallback.
/// - Невалидный UTF-8 при открытии — ошибка, а не пустая строка (защита от затирания оригинала пустым автосейвом).
/// - Запись пробрасывает ошибки наружу; вызывающие стороны не обновляют метку сохранности при неуспехе.
enum DocumentFileError: LocalizedError {
    /// Файл прочитан, но байты не являются валидным UTF-8.
    case invalidUTF8(url: URL)
    /// Атомарная запись не удалась (диск переполнен, нет прав, папка исчезла и т.п.).
    case writeFailed(url: URL, underlying: Error)
    /// Недопустимое имя для rename (слеш, уход наверх, пустое).
    case invalidFileName(String)

    var errorDescription: String? {
        switch self {
        case .invalidUTF8(let url):
            return "Файл «\(url.lastPathComponent)» не является валидным UTF-8 и не открыт, чтобы не затереть оригинал пустым текстом."
        case .writeFailed(let url, let underlying):
            return "Не удалось записать «\(url.path)»: \(underlying.localizedDescription)"
        case .invalidFileName(let name):
            return "Недопустимое имя файла «\(name)»: запрещены «/», «\\» и «..»."
        }
    }
}

/// R6: файловый I/O-сервис, вырезанный из ContentView. Без SwiftUI-зависимостей.
/// Отвечает за: чтение, атомарную запись, rename, autosave с debounce
/// (DispatchWorkItem, 1.0s — тайминги сохранены), периодическое сохранение,
/// watcher-glue.
///
/// Этап 1 (устранение потери данных):
/// - Сериализация debounce + periodic через единый serial `ioQueue`
///   (запись в фоне, не главный поток) и отмену `autosaveWork` перед
///   применением внешних изменений (вызывает владелец).
/// - Подавление собственных событий вотчера токеном собственных записей
///   (`shouldSuppressOwnEvent`), а не сравнением текста с гонкой.
/// - Флаг `isWriteSuspended` запрещает любой автосейв до явного решения
///   пользователя (невалидный UTF-8, внешнее изменение, удаление файла).
final class DocumentFileService {
    /// Debounce-работа autosave (как в исходном ContentView).
    private var autosaveWork: DispatchWorkItem?
    /// Периодический таймер автосохранения.
    private var periodicSaveTimer: Timer?
    /// Watcher внешних изменений — переиспользуется владельцем (ContentView).
    let fileWatcher = FileWatcherService()

    /// Serial очередь всех дисковых записей (debounce + periodic).
    /// Системный snapshot/fileWrapper (`MarkdownDocument`) читает только память
    /// и не пишет напрямую, поэтому сериализация записей здесь достаточна:
    /// последний писатель определяется порядком в этой очереди, а не гонкой потоков.
    private let ioQueue = DispatchQueue(label: "net.duckmd.docfile.io", qos: .utility)
    /// Блокировка для `isWriteSuspended` + токена собственных записей
    /// (доступ с main и с `ioQueue`).
    private let stateLock = NSLock()
    private var suspendedFlag = false
    /// Окно подавления собственных событий вотчера после своей записи.
    /// FS-событие не несёт токен, поэтому токен — это временное окно:
    /// запись фиксирует момент, вотчер игнорирует `.write` внутри окна.
    private var lastOwnWriteAt: Date = .distantPast
    /// Длительность окна подавления (по умолчанию 1.5с — покрывает задержку
    /// DispatchSource между atomic-write и доставкой события).
    var ownWriteSuppressionWindow: TimeInterval = 1.5

    /// Запрет автосейва до явного решения пользователя.
    /// Выставляется владельцем при невалидном UTF-8 / внешнем изменении /
    /// удалении; снимается только явным Apply/Keep/Restore/Close.
    var isWriteSuspended: Bool {
        get { stateLock.sync { suspendedFlag } }
        set { stateLock.sync { suspendedFlag = newValue } }
    }

    // MARK: - I/O

    /// Читать документ с диска. Кидает ошибку FileManager / Cocoa
    /// (в т.ч. на невалидном UTF-8 — контракт `String(contentsOf:encoding:)`).
    func readText(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// Этап 1: читать текст документа для открытия.
    /// Кидает `CocoaError` при недоступности файла (`Data(contentsOf:)`)
    /// и `DocumentFileError.invalidUTF8` при невалидном UTF-8 — больше НЕ
    /// возвращает пустую строку, чтобы пустой автосейв не затёр оригинал.
    /// Владелец (`AppState.openDocument`) при ошибке не создаёт документ
    /// и показывает явную ошибку; автосейв не запускается (документа нет).
    func readDocumentText(at url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DocumentFileError.invalidUTF8(url: url)
        }
        return text
    }

    /// Атомарная запись текста. Этап 1: пробрасывает ошибки наружу
    /// (`DocumentFileError.writeFailed`), без молчаливого подавления.
    /// Вызывающие стороны НЕ обновляют метку сохранности при неуспехе.
    /// Фиксирует токен собственной записи для подавления эха вотчера.
    func writeText(_ text: String, to url: URL) throws {
        markOwnWriteAttempt()
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            markOwnWriteSuccess()
        } catch {
            // Токен уже зафиксирован (запись пыталась идти на диск и могла
            // триггернуть вотчер частичным событием) — не снимаем подавление.
            if let docError = error as? DocumentFileError {
                throw docError
            }
            throw DocumentFileError.writeFailed(url: url, underlying: error)
        }
    }

    // MARK: - Токен собственных записей

    /// Зафиксировать начало собственной записи (расширяет окно подавления
    /// ещё до фактического write, чтобы раннее событие не проскочило).
    private func markOwnWriteAttempt() {
        stateLock.sync { lastOwnWriteAt = Date() }
    }

    /// Зафиксировать успешную собственную запись (обновляет окно).
    private func markOwnWriteSuccess() {
        stateLock.sync { lastOwnWriteAt = Date() }
    }

    /// Проверить, является ли входящее событие вотчера эхом собственной записи.
    /// Вызывается вотчером (через `shouldSuppressOwnEvent`) вместо сравнения
    /// `diskText != lastSavedText`, у которого гонка между чтением и записью.
    func shouldSuppressOwnEvent() -> Bool {
        let last = stateLock.sync { lastOwnWriteAt }
        return Date().timeIntervalSince(last) < ownWriteSuppressionWindow
    }

    // MARK: - Валидация rename

    /// Чистая валидация имени для rename (Этап 1):
    /// запрет слеша/ухода наверх, пустого имени, NUL.
    /// Возвращает trimmed имя без расширения. Кидает `invalidFileName`.
    static func validatedRename(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DocumentFileError.invalidFileName(name) }
        guard !trimmed.contains("\u{0}") else { throw DocumentFileError.invalidFileName(name) }
        // Запрет слеша (оба варианта) и ухода наверх.
        if trimmed.contains("/") || trimmed.contains("\\") {
            throw DocumentFileError.invalidFileName(name)
        }
        if trimmed == "." || trimmed == ".." || trimmed.contains("..") {
            throw DocumentFileError.invalidFileName(name)
        }
        return trimmed
    }

    /// Переименовать файл (тот же каталог, расширение .md). Кидает ошибку
    /// FileManager / `DocumentFileError.invalidFileName`.
    /// Совпадение пути считается no-op и возвращает исходный URL.
    func rename(from url: URL, to newName: String) throws -> URL {
        let clean = try Self.validatedRename(newName)
        let folder = url.deletingLastPathComponent()
        let newURL = folder.appendingPathComponent(clean).appendingPathExtension("md")
        guard newURL.path != url.path else { return url }
        // Атомарность на уровне FS: moveItem в том же каталоге — rename(2).
        try FileManager.default.moveItem(at: url, to: newURL)
        return newURL
    }

    // MARK: - Autosave (debounce)

    /// Отложенное автосохранение с debounce; по завершении вызывает onSaved
    /// на main, при ошибке — onError на main (метка сохранности НЕ обновляется).
    /// Тайминг как в исходном ContentView: отмена предыдущей работы,
    /// запуск через 1.0 секунду. Запись — в фоне (`ioQueue`), не главный поток.
    /// Не запускается при `isWriteSuspended` (ожидание решения пользователя).
    func scheduleAutosave(
        text: String,
        url: URL,
        onSaved: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        if isWriteSuspended { return }
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isWriteSuspended { return }
            do {
                try self.writeText(text, to: url)
                DispatchQueue.main.async {
                    onSaved(text)
                }
            } catch {
                let captured = error
                DispatchQueue.main.async {
                    onError(captured)
                }
            }
        }
        autosaveWork = work
        ioQueue.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    /// Отменить отложенный autosave (внешнее изменение, ручное сохранение).
    func cancelAutosave() {
        autosaveWork?.cancel()
    }

    // MARK: - Periodic autosave

    /// Запустить периодическое сохранение: каждые `interval` секунд берёт
    /// целевой URL (`targetURL` — на каждый тик, владелец может сменить файл),
    /// текущий текст через `currentText`, пишет только если `isDirty`.
    /// onSaved/onError вызываются на main. Запись — в фоне. При
    /// `isWriteSuspended` тик пропускается (ожидание решения пользователя).
    func startPeriodicAutosave(
        interval: TimeInterval,
        targetURL: @escaping () -> URL?,
        currentText: @escaping () -> String,
        isDirty: @escaping () -> Bool,
        onSaved: @escaping (String) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        periodicSaveTimer?.invalidate()
        guard interval > 0 else { return }
        periodicSaveTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self,
                  self.periodicSaveTimer != nil,
                  !self.isWriteSuspended,
                  let url = targetURL(),
                  isDirty() else { return }
            let text = currentText()
            self.ioQueue.async { [weak self] in
                guard let self = self else { return }
                if self.isWriteSuspended { return }
                do {
                    try self.writeText(text, to: url)
                    DispatchQueue.main.async {
                        onSaved(text)
                    }
                } catch {
                    let captured = error
                    DispatchQueue.main.async {
                        onError(captured)
                    }
                }
            }
        }
    }

    /// Остановить периодический таймер.
    func stopPeriodicAutosave() {
        periodicSaveTimer?.invalidate()
        periodicSaveTimer = nil
    }

    // MARK: - Watcher glue

    /// Начать наблюдение с подавлением собственных записей по токену
    /// и раздельным колбэком удаления (Этап 1: удаление — отдельное состояние,
    /// а не молчаливое пересоздание автосейвом).
    func startWatching(
        url: URL,
        onChanged: @escaping () -> Void,
        onDeleted: @escaping () -> Void = {}
    ) {
        fileWatcher.shouldSuppressOwnEvent = { [weak self] in
            self?.shouldSuppressOwnEvent() ?? false
        }
        fileWatcher.onChanged = onChanged
        fileWatcher.onDeleted = onDeleted
        fileWatcher.start(url: url)
    }

    func stopWatching() {
        fileWatcher.stop()
    }
}

private extension NSLock {
    /// Sync-хелпер без рекурсии. Имя `sync` — чтобы не конфликтовать
    /// со штатным `withLock` новых SDK.
    func sync<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
