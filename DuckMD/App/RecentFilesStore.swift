import Foundation

/// Описание недавнего файла
struct RecentFile: Codable, Identifiable {
    var id = UUID()
    let url: URL
    /// Этап 5: `var` — stale-refresh (HubView.openRecentFile) обновляет
    /// bookmark-данные существующей записи без пересоздания записи.
    var bookmarkData: Data?
    var lastOpened: Date
    var lastModified: Date
    var title: String
    var preview: String
    var wordCount: Int
    var fileSize: Int64
    
    /// Проверить, существует ли файл физически на диске
    var exists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// Варианты сортировки недавних файлов
enum SortOption: String, CaseIterable, Identifiable {
    case lastOpened = "lastOpened"
    case lastModified = "lastModified"
    case name = "name"
    case size = "size"
    
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lastOpened: return "Последнее открытие"
        case .lastModified: return "Дата изменения"
        case .name: return "Имя"
        case .size: return "Размер"
        }
    }
}

/// Класс управления списком недавних файлов
final class RecentFilesStore: ObservableObject {
    static let shared = RecentFilesStore()

    /// UserDefaults-ключ персиста сортировки хаба (SPEC R-HUB-8): rawValue SortOption.
    static let sortOptionDefaultsKey = "DuckMD.sortOption"

    @Published var files: [RecentFile] = [] {
        didSet { invalidateCache() }
    }
    @Published var searchText: String = "" {
        didSet { invalidateCache() }
    }
    /// SPEC R-HUB-8: выбор сортировки переживает перезапуск — загрузка в init, запись в didSet.
    @Published var sortOption: SortOption {
        didSet {
            persistSortOption()
            invalidateCache()
        }
    }

    /// Кеш отфильтрованных и отсортированных файлов для производительности при большом количестве недавних файлов
    private var cachedFilteredSorted: [RecentFile]?

    private let fileManager = FileManager.default
    private var saveURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let duckFolder = appSupport.appendingPathComponent("DuckMD", isDirectory: true)
        try? fileManager.createDirectory(at: duckFolder, withIntermediateDirectories: true)
        return duckFolder.appendingPathComponent("recent.json")
    }

    /// Чистый резолв сохранённой сортировки (для персиста и юнит-теста roundtrip).
    static func resolveSortOption(raw: String?) -> SortOption {
        raw.flatMap(SortOption.init(rawValue:)) ?? .lastOpened
    }

    private init() {
        self.sortOption = Self.resolveSortOption(raw: UserDefaults.standard.string(forKey: Self.sortOptionDefaultsKey))
        load()
    }
    
    /// Канонический путь для надёжного сравнения файлов (устраняет расхождения NFC/NFD, симлинков и URL-стандартов)
    static func canonicalPath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping
    }

    func load() {
        guard let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([RecentFile].self, from: data) else {
            return
        }
        // Дедупликация по каноническому пути (если в json были дубликаты из-за разницы кодировок или симлинков)
        var seen = Set<String>()
        var unique: [RecentFile] = []
        for file in decoded where file.exists {
            let canonical = Self.canonicalPath(for: file.url)
            if !seen.contains(canonical) {
                seen.insert(canonical)
                unique.append(file)
            }
        }
        self.files = unique
        save()
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(files) {
            try? data.write(to: saveURL)
        }
    }
    
    /// Добавить или обновить файл в списке недавних.
    /// Этап 3: вызывается с main; тяжёлая работа (stat/preview/wordcount/JSON)
    /// вынесена в addOrUpdateBackground — используйте её для вызовов из debounced
    /// набора текста.
    func addOrUpdate(url: URL, title: String, content: String) {
        let lastOpened = Date()
        let attr = try? fileManager.attributesOfItem(atPath: url.path)
        let lastModified = (attr?[.modificationDate] as? Date) ?? lastOpened
        let fileSize = (attr?[.size] as? Int64) ?? 0
        
        let fileTitle = url.deletingPathExtension().lastPathComponent
        
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        
        let lines = content.components(separatedBy: .newlines)
        var previewText = ""
        var skippedHeader = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            if !skippedHeader && trimmedLine.hasPrefix("#") {
                skippedHeader = true
                continue
            }
            if !previewText.isEmpty {
                previewText += " "
            }
            previewText += trimmedLine
        }
        
        if previewText.isEmpty {
            previewText = content
        }
        
        // Очищаем MD разметку для красивого превью
        let preview = previewText
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(150)
        
        // Создаем security bookmark для восстановления доступа к файлу
        let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        
        let targetCanonical = Self.canonicalPath(for: url)
        if let index = files.firstIndex(where: { Self.canonicalPath(for: $0.url) == targetCanonical }) {
            var file = files[index]
            file.lastOpened = lastOpened
            file.lastModified = lastModified
            file.fileSize = fileSize
            file.title = fileTitle
            file.preview = String(preview)
            file.wordCount = words
            files.remove(at: index)
            files.insert(file, at: 0)
        } else {
            let newFile = RecentFile(
                url: url,
                bookmarkData: bookmarkData,
                lastOpened: lastOpened,
                lastModified: lastModified,
                title: fileTitle,
                preview: String(preview),
                wordCount: words,
                fileSize: fileSize
            )
            files.insert(newFile, at: 0)
        }
        // Лимит недавних файлов из настроек (R9: вместо хардкода 10000).
        // Чистая логика лимита вынесена в applyingLimit (R10) — покрывается юнит-тестами.
        files = Self.applyingLimit(files, limit: SettingsStore.shared.maxRecentFiles)
        save()
    }
    
    /// Этап 3: фоновый вариант addOrUpdate для дебаунса набора текста — stat,
    /// построение preview/wordcount и JSON-кодирование выполняются вне main,
    /// мутация `files` (@Published, UI хаба) и запись на диск — на main.
    /// Потокобезопасность: блокировка защищает files/сохранение от гонки
    /// фонового updater и main-вызовов (remove/save/onAppear).
    private static let stateLock = NSLock()

    func addOrUpdateBackground(url: URL, title: String, content: String) {
        // 1) Тяжёлое — вне main.
        let attr = try? fileManager.attributesOfItem(atPath: url.path)
        let lastModified = (attr?[.modificationDate] as? Date) ?? Date()
        let fileSize = (attr?[.size] as? Int64) ?? 0

        let fileTitle = url.deletingPathExtension().lastPathComponent

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count

        let lines = content.components(separatedBy: .newlines)
        var previewText = ""
        var skippedHeader = false
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedLine.isEmpty { continue }
            if !skippedHeader && trimmedLine.hasPrefix("#") {
                skippedHeader = true
                continue
            }
            if !previewText.isEmpty {
                previewText += " "
            }
            previewText += trimmedLine
        }
        if previewText.isEmpty {
            previewText = content
        }
        let preview = previewText
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(150)

        let targetCanonical = Self.canonicalPath(for: url)
        let limit = SettingsStore.shared.maxRecentFiles

        // 2) Мутация @Published + JSON-запись — на main (сохраняем порядок UI).
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Self.stateLock.lock()
            defer { Self.stateLock.unlock() }
            let lastOpened = Date()
            // Security bookmark создаётся на main (как раньше).
            let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let targetIndex = self.files.firstIndex { Self.canonicalPath(for: $0.url) == targetCanonical }
            if let index = targetIndex {
                var file = self.files[index]
                file.lastOpened = lastOpened
                file.lastModified = lastModified
                file.fileSize = fileSize
                file.title = fileTitle
                file.preview = String(preview)
                file.wordCount = words
                self.files.remove(at: index)
                self.files.insert(file, at: 0)
            } else {
                let newFile = RecentFile(
                    url: url,
                    bookmarkData: bookmarkData,
                    lastOpened: lastOpened,
                    lastModified: lastModified,
                    title: fileTitle,
                    preview: String(preview),
                    wordCount: words,
                    fileSize: fileSize
                )
                self.files.insert(newFile, at: 0)
            }
            self.files = Self.applyingLimit(self.files, limit: limit)
            self.save()
        }
    }

    /// Чистая логика лимита недавних файлов (R10): оставляет не более max(limit, 1)
    /// записей, сохраняя порядок (ожидается «новые в начале»). Вынесена из addOrUpdate
    /// для юнит-тестирования без записи в Application Support.
    static func applyingLimit(_ files: [RecentFile], limit: Int) -> [RecentFile] {
        let capped = max(limit, 1)
        guard files.count > capped else { return files }
        return Array(files.prefix(capped))
    }

    func remove(id: UUID) {
        files.removeAll(where: { $0.id == id })
        save()
    }

    /// Этап 5: обновление security-bookmark для stale-записи (вызывается из
    /// HubView.openRecentFile после успешного резолва с `isStale == true`).
    /// Тихий no-op, если файл уже удалён из списка (гонка с remove) —
    /// поведение открытия при этом не меняется.
    func refreshBookmarkData(canonicalOf url: URL, bookmarkData: Data) {
        let targetCanonical = Self.canonicalPath(for: url)
        guard let index = files.firstIndex(where: { Self.canonicalPath(for: $0.url) == targetCanonical }) else {
            return
        }
        files[index].bookmarkData = bookmarkData
        save()
    }
    
    var filteredAndSortedFiles: [RecentFile] {
        if let cached = cachedFilteredSorted {
            return cached
        }

        var result = files.filter { $0.exists }

        if !searchText.isEmpty {
            result = result.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.preview.localizedCaseInsensitiveContains(searchText) }
        }

        switch sortOption {
        case .lastOpened:
            result.sort { $0.lastOpened > $1.lastOpened }
        case .lastModified:
            result.sort { $0.lastModified > $1.lastModified }
        case .name:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .size:
            result.sort { $0.fileSize > $1.fileSize }
        }

        cachedFilteredSorted = result
        return result
    }

    private func invalidateCache() {
        cachedFilteredSorted = nil
    }

    // MARK: - Персист сортировки (SPEC R-HUB-8)

    /// Записывает выбор сортировки в UserDefaults при каждой смене из UI.
    private func persistSortOption() {
        UserDefaults.standard.set(sortOption.rawValue, forKey: Self.sortOptionDefaultsKey)
    }
}
