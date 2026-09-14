import SwiftUI
import AppKit

/// Главный экран: навигация Хаб ↔ Документ, переключатель режимов, тулбар.
/// Единый источник правды — `document.text` (ObservableObject).
/// R6: файловый I/O (autosave/periodic/rename/watcher-glue) живёт в
/// DocumentFileService; PDFExporter, WindowAccessor, WindowCloseInterceptor,
/// MarkdownGuideView и EmptyStateView вынесены в свои файлы.
struct ContentView: View {
    @ObservedObject var document: MarkdownDocument
    let fileURL: URL?
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var scheme
    @Environment(\.undoManager) private var undoManager
    @State private var fileService = DocumentFileService()
    @State private var showBanner = false
    @State private var secondsRemaining = SettingsStore.shared.extChangeTimerSeconds
    @State private var bannerTimer: Timer? = nil
    /// Этап 1.3: очередь внешних обновлений, ожидающих решения пользователя
    /// (дисковый контент от вотчера и текст модели, не применённый в редактор
    /// из-за фокуса CodeEditorView).
    @State private var pendingExternalTexts: [(text: String, isDiskContent: Bool)] = []
    @State private var hasLocalEdits = false
    @State private var lastSavedText = ""
    @State private var closeInterceptor = WindowCloseInterceptor()
    /// Этап 1.3: диалог «файл удалён» уже показан (защита от повторных onDeleted).
    @State private var isFileDeletedDialogShown = false
    /// Дедуп одинаковых файловых алертов подряд (periodic autosave тикает по таймеру).
    @State private var lastErrorAlertDetails: String? = nil
    @State private var editableFileName: String = ""
    @State private var undoCounter = 0
    @State private var undoObservers: [Any] = []
    @ObservedObject private var recentStore = RecentFilesStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var showMarkdownGuide = false
    @State private var isRenamingExpanded = false
    @State private var isTitleHovered = false
    /// Этап 3: отложенная регистрация в недавних при наборе текста (stat + preview
    /// + JSON write раньше шли на main с каждого нажатия). onAppear/rename/save —
    /// по-прежнему немедленно.
    @State private var recentDebounceWork: DispatchWorkItem? = nil

    var body: some View {
        ZStack(alignment: .top) {
            backgroundLayer

            Group {
                switch appState.editorMode {
                case .rendered:
                    renderedMode
                        .transition(.opacity)
                case .split:
                    splitMode
                        .transition(.opacity)
                case .code:
                    codeMode
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.18), value: appState.editorMode)
            .transition(.move(edge: .trailing).combined(with: .opacity))

            if showBanner {
                ExtChangeBanner(
                    secondsRemaining: secondsRemaining,
                    hasLocalEdits: hasLocalEdits,
                    onApply: { applyExternalChanges() },
                    onCancel: { cancelExternalChanges() },
                    onKeepMine: { keepMyChanges() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showBanner)
        .navigationTitle("")
        .navigationSubtitle("")
        .toolbar { toolbarContent }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .toolbarRole(.editor)

        .onChange(of: document.text) {
            autosave()
            scheduleRecentRegistration()
        }
        // R5: перегенерация HTML при смене настроек — во View-слое (раньше жила
        // в MarkdownDocument). Тот же сигнал и debounce 100ms, что и раньше.
        // regenerateHTML обновляет только renderedHTML: text не меняется →
        // autosave/onDiskWrite не триггерится.
        .onReceive(
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                .map { _ in () }
                .prepend(())
                .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
        ) { _ in
            document.regenerateHTML(theme: .resolved())
        }
        .onAppear {
            registerInRecent()
            lastSavedText = document.text
            startWatching()
            startPeriodicAutosave()
            updateEditableFileName()
            setupUndoObservers()
        }
        .onDisappear {
            stopWatching()
            bannerTimer?.invalidate()
            fileService.stopPeriodicAutosave()
            removeUndoObservers()
        }
        .onChange(of: fileURL) {
            if let newURL = fileURL {
                fileService.startWatching(
                    url: newURL,
                    onChanged: { handleExternalChange() },
                    onDeleted: { handleFileDeleted() }
                )
            }
            updateEditableFileName()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
        .background(
            WindowAccessor(callback: { window in
                if let window = window {
                    closeInterceptor.setup(for: window)
                    closeInterceptor.isDirty = {
                        !SettingsStore.shared.autosaveEnabled && document.text != lastSavedText
                    }
                    closeInterceptor.onConfirmSave = {
                        saveDocument()
                    }
                    if let fileURL = fileURL {
                        window.representedURL = fileURL
                    } else {
                        window.representedURL = nil
                    }
                }
            })
        )
    }

    // MARK: - Autosave (логика — в DocumentFileService, glue — здесь)

    /// Авто-сохранение с дебаунсом при каждом изменении текста.
    /// Этап 1: ошибки записи пробрасываются в алерт с путём (метка сохранности
    /// НЕ обновляется — контракт DocumentFileService).
    private func autosave() {
        guard SettingsStore.shared.autosaveEnabled else { return }
        guard let url = fileURL else { return }
        fileService.scheduleAutosave(
            text: document.text,
            url: url,
            onSaved: { savedText in
                self.lastSavedText = savedText
            },
            onError: { error in
                showFileError(error)
            }
        )
    }

    /// Периодическое автосохранение по таймеру (только если документ изменился).
    /// Этап 1: ошибки записи пробрасываются в алерт с путём.
    private func startPeriodicAutosave() {
        guard SettingsStore.shared.periodicAutosaveEnabled else { return }
        let interval = SettingsStore.shared.autoSaveInterval
        fileService.startPeriodicAutosave(
            interval: interval,
            targetURL: { [weak appState] in appState?.activeFileURL },
            currentText: { [weak document] in document?.text ?? "" },
            isDirty: { [weak document] in document?.text != lastSavedText },
            onSaved: { savedText in
                lastSavedText = savedText
            },
            onError: { error in
                showFileError(error)
            }
        )
    }

    // MARK: - File Watcher

    private func startWatching() {
        guard let url = fileURL else { return }
        fileService.startWatching(
            url: url,
            onChanged: { handleExternalChange() },
            onDeleted: { handleFileDeleted() }
        )
    }

    private func stopWatching() {
        fileService.stopWatching()
    }

    private func handleExternalChange() {
        guard let url = fileURL else { return }
        // Этап 1: ошибка чтения (в т.ч. невалидный UTF-8) — приостанавливаем запись
        // и показываем алерт, чтобы автосейв не затёр внешний файл.
        let diskText: String
        do {
            diskText = try fileService.readText(at: url)
        } catch {
            fileService.cancelAutosave()
            fileService.isWriteSuspended = true
            showUnreadableFileAlert(error, url: url)
            return
        }
        guard diskText != document.text, diskText != lastSavedText else { return }
        fileService.cancelAutosave()
        // Этап 1: запись приостановлена до явного решения пользователя.
        fileService.isWriteSuspended = true
        let isEdited = document.text != lastSavedText
        hasLocalEdits = isEdited
        // Этап 1.3: внешний контент идёт в очередь (применяется последний).
        pendingExternalTexts.append((text: diskText, isDiskContent: true))
        if isEdited {
            showBanner = true
        } else {
            secondsRemaining = SettingsStore.shared.extChangeTimerSeconds
            showBanner = true
            bannerTimer?.invalidate()
            bannerTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
                if secondsRemaining > 1 {
                    secondsRemaining -= 1
                } else {
                    timer.invalidate()
                    applyExternalChanges()
                }
            }
        }
    }

    /// Этап 1.3: внешний текст модели не применён в редакторе (фокус CodeEditorView).
    /// Вместо тихого пропуска — очередь + merge-баннер; модель синхронизируем с
    /// редактором (мои правки — источник правды), внешний текст не теряется.
    private func queueExternalUpdate(external: String, editor: String) {
        guard pendingExternalTexts.last?.text != external else { return }
        fileService.cancelAutosave()
        fileService.isWriteSuspended = true
        pendingExternalTexts.append((text: external, isDiskContent: false))
        if editor != document.text {
            document.text = editor
        }
        hasLocalEdits = true
        bannerTimer?.invalidate()
        showBanner = true
    }

    private func applyExternalChanges() {
        fileService.cancelAutosave()
        showBanner = false
        bannerTimer?.invalidate()
        // Этап 1.3: применяем последний внешний контент из очереди.
        let pending = pendingExternalTexts.last
        pendingExternalTexts.removeAll()
        guard let external = pending?.text, !external.isEmpty else { return }
        // Снимаем фокус с редактора: иначе isEditing не даст применить текст
        // и внешний контент будет потерян при следующей клавише.
        if let window = NSApp.windows.first(where: { $0.isKeyWindow }),
           window.firstResponder is NSTextView {
            window.makeFirstResponder(nil)
        }
        document.previousText = document.text
        document.text = external
        lastSavedText = external
        fileService.isWriteSuspended = false
        // Read-back осмыслен для дискового контента: модельный внешний (очередь
        // редактора) на диске и не обязан присутствовать.
        if pending?.isDiskContent == true, let url = fileURL {
            verifyDiskContent(external, url: url)
        }
    }

    /// Откат внешних изменений (кнопка «Отменить» баннера, SPEC R-EXT-3 / B-02):
    /// отмена = отклонить внешнее, оставить на экране (память) и согласовать диск с памятью.
    /// - previousText есть (после applyExternalChanges): откатываем текст на previousText
    ///   (R9: previousText читается), пишем его, read-back.
    /// - previousText нет (отмена до авто-применения): диск уже содержит внешнюю версию —
    ///   пишем текущий document.text (как keepMyChanges), иначе диск и память остаются
    ///   в расхождении, а снятие suspension открывает автосейв поверх внешнего файла.
    /// lastSavedText синхронизируем только после успешной записи: при успехе иначе
    /// FileWatcher тут же засчитает диск как «внешнее изменение», при ошибке метка
    /// сохранности соврёт. При ошибке записи isWriteSuspended остаётся true —
    /// автосейв заблокирован поверх несогласованного диска; повторная запись —
    /// явным решением (повторная «Отменить» / ручное «Сохранить»).
    private func cancelExternalChanges() {
        fileService.cancelAutosave()
        showBanner = false
        bannerTimer?.invalidate()
        pendingExternalTexts.removeAll()
        if let previous = document.previousText {
            document.text = previous
            document.previousText = nil
        }
        guard let url = fileURL else {
            // Документ без файла: согласовывать нечего — память уже приведена
            // к «тому, что на экране», снимаем suspension.
            lastSavedText = document.text
            fileService.isWriteSuspended = false
            return
        }
        do {
            try fileService.writeText(document.text, to: url)
            lastSavedText = document.text
            verifyDiskContent(document.text, url: url)
            fileService.isWriteSuspended = false
        } catch {
            // Ошибка записи: suspension НЕ снимаем (иначе автосейв пойдёт поверх
            // несогласованного диска), lastSavedText не трогаем — isDirty честный.
            showFileError(error)
        }
    }

    private func keepMyChanges() {
        fileService.cancelAutosave()
        showBanner = false
        bannerTimer?.invalidate()
        pendingExternalTexts.removeAll()
        if let url = fileURL {
            do {
                try fileService.writeText(document.text, to: url)
                lastSavedText = document.text
                verifyDiskContent(document.text, url: url)
            } catch {
                showFileError(error)
            }
        }
        fileService.isWriteSuspended = false
    }

    /// Этап 1.3: файл удалён/перемещён другим приложением (onDeleted).
    /// Запись приостановлена; выбор — восстановить текущий текст или закрыть документ.
    private func handleFileDeleted() {
        fileService.cancelAutosave()
        fileService.isWriteSuspended = true
        showBanner = false
        bannerTimer?.invalidate()
        guard !isFileDeletedDialogShown else { return }
        isFileDeletedDialogShown = true
        let name = fileURL?.lastPathComponent ?? "Файл"
        let alert = NSAlert()
        alert.messageText = "Файл удалён"
        alert.informativeText = "«\(name)» был удалён или перемещён другим приложением.\n\nПуть: \(fileURL?.path ?? "")"
        alert.addButton(withTitle: "Восстановить")
        alert.addButton(withTitle: "Закрыть документ")
        let response = alert.runModal()
        isFileDeletedDialogShown = false
        guard response == .alertFirstButtonReturn, let url = fileURL else {
            closeDeletedDocument()
            return
        }
        do {
            try fileService.writeText(document.text, to: url)
            lastSavedText = document.text
            fileService.isWriteSuspended = false
            // Вотчер мог остаться остановленным (restartWatch не нашёл файл) — перезапускаем.
            startWatching()
            Diag.file.info("Файл восстановлен из редактора, bytes=\(document.text.utf8.count, privacy: .public)")
        } catch {
            showFileError(error)
        }
    }

    /// Этап 1.3: файл не читается при внешнем событии (невалидный UTF-8 / ошибка FS).
    /// Запись приостановлена; явное решение — закрыть документ (безопасно) либо
    /// продолжить без автозаписи: ручное «Сохранить» остаётся явным решением.
    private func showUnreadableFileAlert(_ error: Error, url: URL) {
        Diag.file.error("Файл не читается: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), path=\(url.path, privacy: .private)")
        let details: String
        if let docError = error as? DocumentFileError {
            details = docError.errorDescription ?? docError.localizedDescription
        } else {
            details = "\(error.localizedDescription)\n\nПуть: \(url.path)"
        }
        let alert = NSAlert()
        alert.messageText = "Файл не читается"
        alert.informativeText = details + "\n\nАвтосохранение приостановлено, чтобы не затереть оригинал."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Закрыть документ")
        alert.addButton(withTitle: "Продолжить без записи")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            closeDeletedDocument()
        }
        // «Продолжить без записи»: isWriteSuspended остаётся true —
        // автосейв заблокирован, запись только через явное «Сохранить».
    }

    /// Этап 1.3: закрыть документ, чей файл удалён (без записи на диск).
    private func closeDeletedDocument() {
        fileService.stopWatching()
        fileService.stopPeriodicAutosave()
        appState.activeDocument = nil
        appState.activeFileURL = nil
        appState.showHub = true
    }

    // MARK: - File Errors & Read-back

    /// Единый файловый алерт с путём. Дедуп одинаковых текстов подряд,
    /// чтобы periodic autosave не заспамил модальными окнами.
    private func showFileError(_ error: Error) {
        Diag.file.error("Ошибка файловой операции: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private)")
        let message: String
        var pathHint: String?
        if let docError = error as? DocumentFileError {
            message = docError.errorDescription ?? docError.localizedDescription
            switch docError {
            case .invalidUTF8(let url):
                pathHint = url.path
            case .writeFailed(let url, _):
                pathHint = url.path
            case .invalidFileName:
                pathHint = nil
            }
        } else {
            message = error.localizedDescription
            pathHint = (error as? CocoaError)?.url?.path
        }
        var details = message
        if let pathHint, !message.contains(pathHint) {
            details += "\n\nПуть: \(pathHint)"
        }
        showFileErrorAlert(message: "Ошибка файловой операции", details: details)
    }

    private func showFileErrorAlert(message: String, details: String) {
        guard lastErrorAlertDetails != details else { return }
        lastErrorAlertDetails = details
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.addButton(withTitle: "ОК")
        alert.runModal()
        lastErrorAlertDetails = nil
    }

    /// Этап 1: read-back после записи — перечитать диск и сверить с памятью.
    /// Запись атомарная, поэтому расхождение — признак внешнего вмешательства:
    /// фиксируем диагностикой и показываем алерт.
    private func verifyDiskContent(_ expected: String, url: URL) {
        let diskText: String
        do {
            diskText = try fileService.readText(at: url)
        } catch {
            Diag.file.error("Read-back не удался: type=\(String(describing: type(of: error)), privacy: .public), path=\(url.path, privacy: .private)")
            return
        }
        guard diskText != expected else { return }
        Diag.file.error("Read-back: содержимое на диске отличается от записанного, path=\(url.path, privacy: .private)")
        showFileErrorAlert(
            message: "Файл изменён во время записи",
            details: "Содержимое «\(url.lastPathComponent)» на диске не совпадает с записанным.\n\nПуть: \(url.path)"
        )
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor),
                     Color(nsColor: .textBackgroundColor).opacity(0.6)],
            startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }

    // MARK: - Modes

    @ViewBuilder
    private var renderedMode: some View {
        if document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            ScrollView {
                EmptyStateView()
                    .frame(maxWidth: appState.readingWidth)
                    .padding(.vertical, 60)
            }
        } else {
            WebPreviewView.makeStandard(
                document: document,
                onElementEdited: { line, newText in
                    guard let range = validatedEditPayload(line: line, newText: newText) else { return }
                    let updatedText = RenderEditParser.applyEdit(startLine: range.start, endLine: range.end, newText: newText, to: document.text)
                    updateText(updatedText)
                },
                onTableCellEdited: { line, row, col, newText in
                    guard validatedEditPayload(line: line, newText: newText) != nil else { return }
                    let updatedText = RenderEditParser.applyTableCellEdit(tableLine: line, row: row, col: col, newText: newText, to: document.text)
                    updateText(updatedText)
                },
                onCheckboxToggled: { line, checked in
                    // Валидация payload (семантика validatedEditPayload): line должна
                    // указывать на существующий блок текущего документа.
                    guard line >= 1,
                          document.parsedBlocks.contains(where: { $0.sourceLine == line }),
                          let updatedLines = RenderEditParser.applyCheckboxToggle(lines: document.text.components(separatedBy: "\n"), line: line, checked: checked) else { return }
                    updateText(updatedLines.joined(separator: "\n"))
                },
                updateText: updateText
            )
        }
    }

    @ViewBuilder
    private var codeMode: some View {
        CodeEditorView(
            text: $document.text,
            onPendingExternalText: { external, editor in
                queueExternalUpdate(external: external, editor: editor)
            }
        )
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var splitMode: some View {
        SplitEditorView(
            document: document,
            onPendingExternalText: { external, editor in
                queueExternalUpdate(external: external, editor: editor)
            }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation(.spring(duration: 0.3, bounce: 0.1)) {
                    appState.openHub()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "house")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("В Хаб (⌘[)")
            .keyboardShortcut("[", modifiers: .command)
        }

        ToolbarItem(placement: .principal) {
            let docName = editableFileName.isEmpty ? (fileURL?.deletingPathExtension().lastPathComponent ?? "Документ") : editableFileName
            let fullFileName = fileURL?.lastPathComponent ?? (docName.hasSuffix(".md") ? docName : "\(docName).md")
            Button {
                isRenamingExpanded = true
            } label: {
                VStack(spacing: 1.5) {
                    HStack(spacing: 4) {
                        MarqueeText(
                            text: docName,
                            font: .system(size: 13),
                            fontWeight: .semibold,
                            isHovered: isTitleHovered,
                            maxWidth: 220
                        )
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                    if !wordCountLabel.isEmpty {
                        Text(wordCountLabel)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isTitleHovered ? Color.primary.opacity(0.06) : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isTitleHovered = $0 }
            .help(fullFileName)
            .popover(isPresented: $isRenamingExpanded, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Имя документа")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    
                    TextField("Имя файла", text: $editableFileName, onCommit: {
                        confirmRename()
                        isRenamingExpanded = false
                    })
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(width: 220)
                    .onSubmit {
                        confirmRename()
                        isRenamingExpanded = false
                    }
                    
                    HStack {
                        Button("Отмена") {
                            cancelRename()
                            isRenamingExpanded = false
                        }
                        .keyboardShortcut(.cancelAction)
                        
                        Spacer()
                        
                        Button("Применить") {
                            confirmRename()
                            isRenamingExpanded = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(14)
            }
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Режим", selection: $appState.editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Image(systemName: mode.systemImage).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Режим отображения (⌘1, ⌘2, ⌘3)")

            Menu {
                Button {
                    copyAsPlainText()
                } label: {
                    Label("Копировать текст", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Divider()

                Button {
                    exportPDF()
                } label: {
                    Label("Экспорт в PDF…", systemImage: "doc.text.image")
                }

                Button {
                    exportHTMLFile()
                } label: {
                    Label("Экспорт в HTML…", systemImage: "globe")
                }

                Divider()

                Button {
                    saveDocumentAs()
                } label: {
                    Label("Сохранить как…", systemImage: "doc.badge.plus")
                }

                Button {
                    saveDocument()
                } label: {
                    Label("Сохранить", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .help("Поделиться и экспортировать")

            Button {
                showMarkdownGuide.toggle()
            } label: {
                Image(systemName: "info.circle")
            }
            .help("Markdown шпаргалка")
            .popover(isPresented: $showMarkdownGuide) {
                MarkdownGuideView()
            }
        }
    }


    private func updateText(_ newText: String) {
        TextEditApplier.apply(newText, to: document, undoManager: undoManager)
    }

    // MARK: - Helpers

    /// Валидация payload из webview (editContentHandler): `line` должна указывать
    /// на существующий блок в текущих `parsedBlocks`, текст — обычная строка
    /// без NUL. Невалидные сообщения игнорируются (защита от XSS-подмены строк).
    private func validatedEditPayload(line: Int, newText: String) -> (start: Int, end: Int)? {
        guard line >= 1,
              !newText.contains("\u{0}"),
              let block = document.parsedBlocks.first(where: { $0.sourceLine == line }),
              let endLine = block.endLine else {
            return nil
        }
        return (start: line, end: endLine)
    }

    private var documentTitle: String {
        let firstLine = document.text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
        return firstLine?.isEmpty == false ? firstLine! : "Без названия"
    }

    private var wordCountLabel: String {
        let trimmed = document.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let words = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        let readingMin = max(1, Int(Double(words.count) / 200.0))
        return "\(words.count) слов · ~\(readingMin) мин чтения"
    }

    private func copyAsPlainText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(document.text, forType: .string)
    }

    private func saveDocumentAs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.markdownDoc]
        savePanel.nameFieldStringValue = documentTitle + ".md"
        if !SettingsStore.shared.defaultSavePath.isEmpty {
            savePanel.directoryURL = URL(fileURLWithPath: SettingsStore.shared.defaultSavePath)
        }
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }
        do {
            try document.text.write(to: saveURL, atomically: true, encoding: .utf8)
            lastSavedText = document.text
            appState.activeFileURL = saveURL
            registerInRecent()
            Diag.file.info("Файл сохранён вручную, bytes=\(document.text.utf8.count, privacy: .public)")
        } catch {
            Diag.file.error("Ошибка сохранения файла: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), path=\(saveURL.path, privacy: .private)")
            showFileError(error)
        }
    }

    /// Этап 1: ручное сохранение — ошибки записи в алерт с путём;
    /// метка сохранности обновляется только при успехе.
    private func saveDocument() {
        fileService.cancelAutosave()
        guard let url = fileURL else {
            saveDocumentAs()
            return
        }
        do {
            try fileService.writeText(document.text, to: url)
            lastSavedText = document.text
            verifyDiskContent(document.text, url: url)
        } catch {
            showFileError(error)
        }
    }

    private func updateEditableFileName() {
        if let url = fileURL {
            editableFileName = url.deletingPathExtension().lastPathComponent
        } else {
            editableFileName = "Без названия"
        }
    }

    private func renameFile() {
        guard let url = fileURL else { return }
        let trimmed = editableFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            updateEditableFileName()
            return
        }

        // Этап 1: предварительная валидация имени (validatedRename) — явный
        // алерт на недопустимое имя до обращения к файловой системе.
        if (try? DocumentFileService.validatedRename(trimmed)) == nil {
            showFileError(DocumentFileError.invalidFileName(trimmed))
            updateEditableFileName()
            return
        }

        let folder = url.deletingLastPathComponent()
        let newURL = folder.appendingPathComponent(trimmed).appendingPathExtension("md")

        if newURL.path == url.path {
            return
        }

        if FileManager.default.fileExists(atPath: newURL.path) {
            let alert = NSAlert()
            alert.messageText = "Файл с таким именем уже существует"
            alert.informativeText = "Пожалуйста, выберите другое имя."
            alert.addButton(withTitle: "ОК")
            alert.runModal()
            updateEditableFileName()
            return
        }

        do {
            stopWatching()
            // Этап 1: rename возвращает фактический URL — атомарно обновляем
            // документ, вотчер и недавние от него (без дублирования вычисления пути).
            let renamedURL = try fileService.rename(from: url, to: trimmed)

            if let oldRecent = recentStore.files.first(where: { $0.url.path == url.path }) {
                recentStore.remove(id: oldRecent.id)
            }

            appState.activeFileURL = renamedURL
            // SPEC R-MD-9: URL документа сменился — резолв картинок от новой папки.
            document.documentURL = renamedURL
            // Вотчер перезапускаем явно на новый URL: self.fileURL ещё старый
            // до ре-рендера; повторный start из .onChange(of: fileURL) безвреден.
            fileService.startWatching(
                url: renamedURL,
                onChanged: { handleExternalChange() },
                onDeleted: { handleFileDeleted() }
            )
            registerInRecent(renamedURL)
        } catch {
            showFileError(error)
            updateEditableFileName()
            startWatching()
        }
    }

    private func confirmRename() {
        renameFile()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isRenamingExpanded = false
        }
    }

    private func cancelRename() {
        updateEditableFileName()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isRenamingExpanded = false
        }
    }

    /// Обёртка статического HTML для экспорта (HTML/PDF). Генерация body-HTML —
    /// уже существующий путь MarkdownToHTML (.export); здесь только шаблон документа.
    private func wrapHTMLDocument(_ bodyHTML: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <style>
        body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;max-width:720px;margin:40px auto;padding:0 20px;line-height:1.6;color:#1d1d1f}
        code{background:rgba(0,0,0,.06);padding:2px 5px;border-radius:4px;font-family:ui-monospace,monospace}
        pre{background:#f6f6f8;padding:12px;border-radius:8px;overflow:auto}
        blockquote{border-left:3px solid #FFC700;margin:0;padding-left:12px;color:#555}
        h1,h2,h3{line-height:1.2}
        table{border-collapse:collapse}td,th{border:1px solid #ddd;padding:6px 10px}
        </style></head><body>\(bodyHTML)</body></html>
        """
    }

    private func exportHTMLFile() {
        // Логика генерации HTML — MarkdownToHTML (.export); View только показывает
        // панель сохранения и пишет файл.
        let html = MarkdownToHTML.convert(document.text, mode: .export)
        let wrapped = wrapHTMLDocument(html)
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.html]
        savePanel.nameFieldStringValue = documentTitle + ".html"
        if !SettingsStore.shared.defaultSavePath.isEmpty {
            savePanel.directoryURL = URL(fileURLWithPath: SettingsStore.shared.defaultSavePath)
        }
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }
        do {
            try wrapped.data(using: .utf8)?.write(to: saveURL)
        } catch {
            // Этап 1: ошибки экспорта — алерт с путём вместо молчаливого try?.
            showFileError(error)
        }
    }

    private func exportPDF() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.nameFieldStringValue = documentTitle + ".pdf"
        if !SettingsStore.shared.defaultSavePath.isEmpty {
            savePanel.directoryURL = URL(fileURLWithPath: SettingsStore.shared.defaultSavePath)
        }
        guard savePanel.runModal() == .OK, let saveURL = savePanel.url else { return }
        let html = MarkdownToHTML.convert(document.text, mode: .export, baseURL: fileURL)
        let wrapped = wrapHTMLDocument(html)
        // Этап 3: baseURL документа пробрасывается в PDF — локальные картинки
        // (file://, резолвнутые resolveImage Этапа 2) загружаются в webview.
        PDFExporter.export(html: wrapped, to: saveURL, baseURL: fileURL)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        DocumentDropHelper.handleStandardDrop(providers: providers, appState: appState) {
            // Открываем конвертер
            if let openWindow = NSApp.windows.first(where: { $0.title == "Конвертер Markdown" }) {
                openWindow.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Этап 1: URL можно передать явно (после rename fileURL ещё старый до ре-рендера).
    private func registerInRecent(_ url: URL? = nil) {
        guard let url = url ?? fileURL else { return }
        RecentFilesStore.shared.addOrUpdate(url: url, title: documentTitle, content: document.text)
    }

    /// Этап 3: регистрация в недавних при наборе — дебаунс 1с. Тяжёлая часть
    /// (stat/preview/wordcount) уходит с main: work item после дебаунса хопит
    /// на global(qos: .utility) — снимок текста берётся до ухода; мутация
    /// `files` (@Published, UI хаба) и JSON-запись остаются на main
    /// (внутри addOrUpdateBackground).
    private func scheduleRecentRegistration() {
        guard let url = fileURL else { return }
        recentDebounceWork?.cancel()
        let textSnapshot = document.text
        let work = DispatchWorkItem { [weak recentStore = RecentFilesStore.shared] in
            DispatchQueue.global(qos: .utility).async {
                recentStore?.addOrUpdateBackground(
                    url: url, title: url.deletingPathExtension().lastPathComponent, content: textSnapshot)
            }
        }
        recentDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func setupUndoObservers() {
        let center = NotificationCenter.default
        // Слушаем только undo-менеджер этого view (object:), чтобы не ловить
        // checkpoint'ы чужих менеджеров (меню, текстовые поля и т.д.).
        let obs1 = center.addObserver(forName: Notification.Name.NSUndoManagerCheckpoint, object: undoManager, queue: .main) { [weak undoManager] _ in
            guard undoManager != nil else { return }
            self.undoCounter += 1
        }
        let obs2 = center.addObserver(forName: Notification.Name.NSUndoManagerDidUndoChange, object: undoManager, queue: .main) { _ in
            self.undoCounter += 1
        }
        let obs3 = center.addObserver(forName: Notification.Name.NSUndoManagerDidRedoChange, object: undoManager, queue: .main) { _ in
            self.undoCounter += 1
        }
        self.undoObservers = [obs1, obs2, obs3]
    }
    
    private func removeUndoObservers() {
        let center = NotificationCenter.default
        for observer in undoObservers {
            center.removeObserver(observer)
        }
        undoObservers.removeAll()
    }
}
