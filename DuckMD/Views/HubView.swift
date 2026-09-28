import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Главное окно-хаб (Welcome Window) для DuckMD.
struct HubView: View {
    @ObservedObject private var store = RecentFilesStore.shared
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    @State private var isConverting = false
    @State private var errorMessage: String? = nil
    @State private var showErrorAlert = false
    /// Состояние targeted у существующего onDrop хаба.
    @State private var isTargeted = false

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            if store.filteredAndSortedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 20) {
                    hubActionRow
                    Divider()
                        .padding(.vertical, 4)
                    recentFilesHeader
                    emptyRecentPlaceholder
                }
                .padding(20)
            } else {
                // Единственный ребёнок ScrollView: обёртка VStack/LazyVStack
                // заставляет сетку измерить все строки сразу.
                LazyVGrid(columns: columns, spacing: 14) {
                    Section {
                        ForEach(store.filteredAndSortedFiles) { file in
                            HubCardView(
                                file: file,
                                onOpen: { openRecentFile(file) },
                                onRemove: { store.remove(id: file.id) }
                            )
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 20) {
                            hubActionRow
                            Divider()
                                .padding(.vertical, 4)
                            recentFilesHeader
                        }
                        // spacing сетки 14; раньше зазор шапка→карточки был 20.
                        .padding(.bottom, 6)
                    }
                }
                .padding(20)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
            .navigationTitle("")
            .navigationSubtitle("")
            .toolbarBackground(.hidden, for: .windowToolbar)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    HStack(spacing: 7) {
                        DuckLogo(size: 18)
                        Text("DuckMD")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 12)
                }

                ToolbarItem(placement: .principal) {
                    Spacer()
                }

                ToolbarItem(placement: .primaryAction) {
                    NativeSearchField(text: $store.searchText)
                        .frame(width: 185, height: 22)
                }

                ToolbarItem(placement: .primaryAction) {
                    SettingsLink {
                        Image(systemName: "gearshape")
                    }
                    .help("Настройки")
                }
            }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            handleDrop(providers: providers)
        }
        .fileDropOverlay(isPresented: isTargeted, mode: .open)
        .onAppear {
            store.load()
        }
        .overlay {
            if isConverting {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text("Конвертация документа...")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
                }
            }
        }
        .alert("Ошибка конвертации", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Произошла ошибка при конвертации")
        }
        .alert("Конвертация завершена", isPresented: $showSavedNotice) {
            Button("Открыть", role: .cancel) { }
        } message: {
            Text(savedNoticePath ?? "")
        }
    }

    // MARK: - Headers & Placeholders

    /// Три действия хаба. Всегда в зоне видимости, не в ленивом списке карточек.
    private var hubActionRow: some View {
        HStack {
            Spacer(minLength: 0)
            LazyVGrid(columns: [
                GridItem(.flexible(minimum: 140, maximum: 220), spacing: 14),
                GridItem(.flexible(minimum: 140, maximum: 220), spacing: 14),
                GridItem(.flexible(minimum: 140, maximum: 220), spacing: 14)
            ], spacing: 14) {
                HubActionCard(
                    icon: "doc.badge.plus",
                    title: "Новый документ",
                    isAccent: true
                ) {
                    appState.createNewDocument()
                }

                HubActionCard(
                    icon: "folder.badge.plus",
                    title: "Открыть существующий",
                    isAccent: false
                ) {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.markdownDoc, .markdownStandard, .plainText]
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.openDocument(at: url)
                    }
                }

                HubActionCard(
                    icon: "arrow.triangle.2.circlepath.doc.on.clipboard",
                    title: "Конвертировать в MD",
                    isAccent: false
                ) {
                    convertAndOpenDocument()
                }
            }
            .frame(maxWidth: 720)
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
    }

    private var recentFilesHeader: some View {
        HStack {
            Text("Недавние файлы")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.secondary)
            Spacer()
            
            // Нативная сортировка macOS, срабатывающая сразу по первому клику
            Menu {
                ForEach(SortOption.allCases) { option in
                    Button {
                        store.sortOption = option
                    } label: {
                        HStack {
                            Text(option.label)
                            if store.sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(store.sortOption.label)
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.9))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var emptyRecentPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            DuckLogo(size: 48)
                .opacity(0.3)
            Text(store.searchText.isEmpty ? "Нет недавних файлов" : "Ничего не найдено")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            Text(store.searchText.isEmpty ? "Создайте документ или перетащите файл сюда" : "Попробуйте изменить поисковый запрос")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.05), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }

    // MARK: - Helper Methods

    /// Этап 5 (контракт security-scoped доступа): scoped-доступ из bookmark
    /// держится открытым строго на время СИНХРОННОГО чтения в
    /// `AppState.openDocument` и освобождается сразу после возврата —
    /// дальнейший I/O (вотчер, автосейв) идёт по обычному пути (без песочницы,
    /// D-25, scoped-флаг вне sandbox — no-op, но контракт держим явно).
    /// Stale bookmark: если резолв успешен, но `isStale`, пробуем обновить
    /// bookmark-данные в store, чтобы следующий запуск не деградировал до
    /// fallback по `file.url`; при ошибке резолва — fallback по сохранённому URL.
    private func openRecentFile(_ file: RecentFile) {
        guard let bookmarkData = file.bookmarkData else {
            appState.openDocument(at: file.url)
            return
        }

        var isStale = false
        do {
            let resolvedURL = try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            let accessing = resolvedURL.startAccessingSecurityScopedResource()
            defer { if accessing { resolvedURL.stopAccessingSecurityScopedResource() } }

            appState.openDocument(at: resolvedURL)

            if isStale, let fresh = try? resolvedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                store.refreshBookmarkData(canonicalOf: resolvedURL, bookmarkData: fresh)
            }
        } catch {
            appState.openDocument(at: file.url)
        }
    }

    private func convertAndOpenDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .pdf, .rtf, .html, .plainText,
            UTType(importedAs: "com.microsoft.word.doc"),
            UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "Выберите документ для конвертации в Markdown"
        panel.prompt = "Конвертировать"

        if panel.runModal() == .OK, let url = panel.url {
            // SPEC R-CONV-3: одиночная конвертация из кнопки — NSSavePanel
            // (пользователь выбирает папку и имя), затем конвертация и открытие.
            let savePanel = NSSavePanel()
            savePanel.allowedContentTypes = [.markdownDoc]
            savePanel.nameFieldStringValue = url.deletingPathExtension().appendingPathExtension("md").lastPathComponent
            if let folder = Self.defaultSaveFolder() {
                savePanel.directoryURL = folder
            }
            guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }
            convertToFile(url: url, targetURL: saveURL, notifySaved: false)
        }
    }

    /// Этап 2: безопасный дефолт-путь БЕЗ force-unwrap (было urls(for:).first!):
    /// явный дефолт ~/Documents/DuckMD при недоступном documentDirectory — nil.
    private static func defaultSaveFolder() -> URL? {
        let custom = SettingsStore.shared.defaultSavePath
        if !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return docs.appendingPathComponent("DuckMD", isDirectory: true)
    }

    /// Уникальное имя «Name (N).md» в папке (для drop-очереди без SavePanel).
    private static func uniquedTargetURL(in folder: URL, sourceURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var target = folder.appendingPathComponent(sourceURL.deletingPathExtension().appendingPathExtension("md").lastPathComponent)
        var counter = 1
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(baseName) (\(counter)).md")
            counter += 1
        }
        return target
    }

    /// Этап 2 (SPEC N-7): подача в конвертацию с защитой от дубликатов:
    /// два drop-события не должны поставить один и тот же файл в очередь.
    private func enqueueConversion(_ urls: [URL]) {
        let newOnes = urls.filter { url in !conversionQueue.contains(url) }
        conversionQueue.append(contentsOf: newOnes)
        processNextConversion()
    }

    /// Последовательная обработка очереди (Этап 2): параллельный convertAndOpen
    /// перезаписывал цель и isConverting — теперь по одному файлу.
    private func processNextConversion() {
        guard !isConverting, !conversionQueue.isEmpty, let url = conversionQueue.first else { return }
        conversionQueue.removeFirst()
        convertAndOpen(url: url)
    }

    private func convertAndOpen(url: URL) {
        isConverting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak appState] in
            do {
                let md = try ConverterService.convert(url: url)

                // Этап 2: defaultSavePath без force-unwrap (SPEC N-7 + R-CONV-3).
                guard let saveFolder = Self.defaultSaveFolder() else {
                    throw ConversionError.loadFailed
                }
                try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
                let targetURL = Self.uniquedTargetURL(in: saveFolder, sourceURL: url)

                try md.write(to: targetURL, atomically: true, encoding: .utf8)

                DispatchQueue.main.async {
                    self.isConverting = false
                    // Уведомление «сохранено в …» вместо молчаливой записи.
                    self.savedNoticePath = targetURL.path
                    self.showSavedNotice = true
                    appState?.openDocument(at: targetURL)
                    self.processNextConversion()
                }
            } catch {
                Diag.export.error("Ошибка конвертации: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), srcExt=\(Diag.ext(url), privacy: .public)")
                DispatchQueue.main.async {
                    self.isConverting = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                    self.processNextConversion()
                }
            }
        }
    }

    /// Конвертация в явно выбранный пользователем путь (NSSavePanel, R-CONV-3).
    private func convertToFile(url: URL, targetURL: URL, notifySaved: Bool) {
        isConverting = true
        DispatchQueue.global(qos: .userInitiated).async { [weak appState] in
            do {
                let md = try ConverterService.convert(url: url)
                try md.write(to: targetURL, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self.isConverting = false
                    if notifySaved {
                        self.savedNoticePath = targetURL.path
                        self.showSavedNotice = true
                    }
                    appState?.openDocument(at: targetURL)
                    self.processNextConversion()
                }
            } catch {
                Diag.export.error("Ошибка конвертации: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), srcExt=\(Diag.ext(url), privacy: .public)")
                DispatchQueue.main.async {
                    self.isConverting = false
                    self.errorMessage = error.localizedDescription
                    self.showErrorAlert = true
                    self.processNextConversion()
                }
            }
        }
    }

    private func openConverterWindow() {
        openWindow(id: "converter")
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let window = NSApp.windows.first(where: { $0.title == "Конвертер документов в MD" }) {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Этап 2: очередь дропов обрабатывается ПОСЛЕДОВАТЕЛЬНО.
    @State private var conversionQueue: [URL] = []
    @State private var showSavedNotice = false
    @State private var savedNoticePath: String? = nil

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var markdownURLs: [URL] = []
        var convertURLs: [URL] = []
        for provider in providers {
            DocumentDropHelper.extractURL(from: provider) { url in
                DispatchQueue.main.async {
                    if DocumentDropHelper.isMarkdown(url) {
                        markdownURLs.append(url)
                    } else {
                        convertURLs.append(url)
                    }
                    // Обрабатываем, когда все провайдеры события отработали.
                    if markdownURLs.count + convertURLs.count == providers.count {
                        markdownURLs.forEach { appState.openDocument(at: $0) }
                        enqueueConversion(convertURLs)
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Action Card Component

struct HubActionCard: View {
    let icon: String
    let title: String
    let isAccent: Bool
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 26))
                .foregroundColor(isAccent ? .accentColor : .primary)
            Text(title)
                .font(.system(size: 13, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(height: 34, alignment: .center)
                .padding(.horizontal, 8)
            Spacer()
        }
        .frame(height: 136)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isAccent ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : AnyShapeStyle(.regularMaterial))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? (isAccent ? Color.accentColor : Color.primary.opacity(0.2)) : Color.clear, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.01), radius: isHovered ? 6 : 2, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.98 : (isHovered ? 1.02 : 1.0))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            isPressed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                isPressed = false
                action()
            }
        }
    }
}
