import Foundation

/// Сервис отслеживания внешних изменений файла на базе DispatchSource.
/// Этап 1: подавление собственных записей по токену (а не сравнением текста),
/// раздельный колбэк удаления (удаление — отдельное состояние, а не эхо write).
final class FileWatcherService {
    private var fileDescriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?
    /// URL последнего запуска наблюдения — нужен для восстановления после .delete/.rename
    private var watchedURL: URL?
    private let queue = DispatchQueue(label: "net.duckmd.filewatcher", qos: .background)

    /// Замыкание, вызываемое при обнаружении изменения файла
    var onChanged: (() -> Void)?
    /// Этап 1: файл удалён/перемещён (нет на прежнем пути) — владелец показывает
    /// состояние «удалён» с выбором восстановить/закрыть, автосейв приостановлен.
    var onDeleted: (() -> Void)?
    /// Этап 1: токен собственных записей владельца (`DocumentFileService`).
    /// Вызывается на фоновой `queue` вотчера; реализация владельца потокобезопасна (NSLock).
    /// Если true и событие — только `.write` без `.delete`/`.rename`,
    /// событие игнорируется как эхо собственной записи.
    var shouldSuppressOwnEvent: (() -> Bool)?

    /// Начать наблюдение за файлом по URL
    func start(url: URL) {
        stop()
        self.watchedURL = url

        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // G-DIAG: errno — публичный код, путь приватный.
            Diag.watcher.error("Не удалось открыть файловый дескриптор для watch: errno=\(errno, privacy: .public), path=\(url.path, privacy: .private)")
            return
        }
        self.fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self = self else { return }
            let flags = source.data
            let isWrite = flags.contains(.write)
            let isRename = flags.contains(.rename)
            let isDelete = flags.contains(.delete)
            // G-DIAG: событие — публичная метрика; путь приватный.
            Diag.watcher.debug("Событие watch: write=\(isWrite, privacy: .public), rename=\(isRename, privacy: .public), delete=\(isDelete, privacy: .public)")

            // 1. Подавление собственного эха (автосейв DuckMD):
            // На APFS атомарная запись (write to temp + rename) доставляет .delete или .rename
            // к старому файловому дескриптору. Если активно окно подавления собственной записи —
            // это наше собственное сохранение: игнорируем событие, перезапускаем вотчер при смене inode
            // и выходим без вызова onDeleted или onChanged.
            if self.shouldSuppressOwnEvent?() == true {
                Diag.watcher.debug("Подавлено эхо собственной записи (write=\(isWrite, privacy: .public), rename=\(isRename, privacy: .public), delete=\(isDelete, privacy: .public))")
                if isDelete || isRename {
                    self.restartWatch()
                }
                return
            }

            // 2. Внешнее событие удаления / атомарной перезаписи (.delete):
            if isDelete {
                // Если файл всё ещё существует на диске — это внешняя атомарная перезапись (например, сторонний редактор)
                let stillExists = FileManager.default.fileExists(atPath: url.path)
                if stillExists {
                    Diag.watcher.debug("Внешняя атомарная запись (delete-событие, но файл существует на диске)")
                    DispatchQueue.main.async { [weak self] in self?.onChanged?() }
                } else {
                    DispatchQueue.main.async { [weak self] in self?.onDeleted?() }
                }
                self.restartWatch()
                return
            }

            // 3. Внешнее событие перемещения / переименования (.rename):
            if isRename {
                let stillExists = FileManager.default.fileExists(atPath: url.path)
                if !stillExists {
                    DispatchQueue.main.async { [weak self] in self?.onDeleted?() }
                } else {
                    DispatchQueue.main.async { [weak self] in self?.onChanged?() }
                }
                self.restartWatch()
                return
            }

            // 4. Внешнее событие обычной записи (.write):
            if isWrite {
                DispatchQueue.main.async { [weak self] in self?.onChanged?() }
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        self.source = source
        source.resume()
    }

    /// Остановить наблюдение
    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    /// Пересоздать источник по последнему известному URL (атомарная запись или
    /// rename с сохранением пути). Если файл недоступен — watch остаётся
    /// остановленным до следующего start(url:) со стороны владельца.
    private func restartWatch() {
        guard let url = watchedURL else { return }
        // Небольшая задержка: атомарная запись (write-temp + rename) может
        // доставить delete раньше, чем новый inode появится на пути.
        // Одна попытка; при отсутствии файла остаёмся остановленными —
        // владелец уже получил onDeleted и показывает состояние «удалён».
        queue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, let current = self.watchedURL else { return }
            guard current.path == url.path else { return }
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            DispatchQueue.main.async { [weak self] in
                // Перезапускаем только если владелец не переключил URL
                // (rename в ContentView делает stop + start с новым URL).
                guard let self = self, self.watchedURL?.path == url.path else { return }
                self.start(url: url)
            }
        }
    }

    deinit {
        stop()
    }
}
