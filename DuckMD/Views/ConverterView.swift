import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Экран конвертации различных форматов в Markdown (DOCX, PDF, RTF, HTML, TXT)
struct ConverterView: View {
    @EnvironmentObject private var appState: AppState
    
    @State private var fileURL: URL? = nil
    @State private var conversionResult: String = ""
    @State private var isConverting = false
    @State private var errorMessage: String? = nil

    /// Этап 5: последовательная очередь дроп-файлов (по образцу хаба,
    /// HubView.enqueueConversion): защита от дубликатов + processNext —
    /// мультидроп не теряет файлы при активной конвертации.
    @State private var dropQueue: [URL] = []
    
    var body: some View {
        VStack(spacing: 0) {
            // Шапка
            headerView
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
            
            Divider()
            
            // Тело
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(VisualEffectView(material: .windowBackground, blendingMode: .behindWindow))
            
            Divider()
            
            // Подвал
            footerView
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(VisualEffectView(material: .titlebar, blendingMode: .withinWindow))
        }
        .frame(width: 560, height: 440)
        .onAppear {
            // Если пришли из Хаба по Drag-and-Drop
            if let pending = appState.pendingConversionURL {
                fileURL = pending
                appState.pendingConversionURL = nil
                startConversion()
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var headerView: some View {
        HStack {
            Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
            Text("Конвертер документов в MD")
                .font(.system(size: 15, weight: .bold))
            Spacer()
        }
    }
    
    private var contentView: some View {
        VStack(spacing: 16) {
            if fileURL == nil {
                // Зона сброса файлов
                VStack(spacing: 12) {
                    Image(systemName: "doc.badge.arrow.up")
                        .font(.system(size: 44))
                        .foregroundColor(.secondary)
                        
                    Text("Перетащите файл сюда")
                        .font(.system(size: 15, weight: .bold))
                        
                    Text("Поддерживаются DOCX, PDF, RTF, HTML, TXT")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        
                    Button("Выбрать файл...") {
                        selectFile()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.02))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.secondary.opacity(0.2), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 4]))
                )
                .padding(20)
            } else if isConverting {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Конвертируем...")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !conversionResult.isEmpty {
                // Предпросмотр результата
                VStack(alignment: .leading, spacing: 8) {
                    Text("Предпросмотр результата:")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(conversionResult)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                }
                .padding(20)
            } else if let error = errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "xmark.octagon")
                        .font(.system(size: 40))
                        .foregroundColor(.red)
                    Text("Ошибка конвертации")
                        .font(.system(size: 14, weight: .bold))
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Button("Попробовать снова") {
                        fileURL = nil
                        errorMessage = nil
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var footerView: some View {
        HStack {
            if let file = fileURL {
                Text(file.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 240, alignment: .leading)
            }
            
            Spacer()
            
            if fileURL != nil && conversionResult.isEmpty && !isConverting && errorMessage == nil {
                Button("Сбросить") {
                    fileURL = nil
                }
                .buttonStyle(.bordered)
                
                Button("Конвертировать") {
                    startConversion()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            } else if !conversionResult.isEmpty {
                Button("Сбросить") {
                    fileURL = nil
                    conversionResult = ""
                }
                .buttonStyle(.bordered)
                
                Button("Сохранить как .md...") {
                    saveMarkdown()
                }
                .buttonStyle(.bordered)
                
                Button("Открыть в редакторе") {
                    openInEditor()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
    }
    
    // MARK: - Логика действий
    
    private func selectFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .pdf, .rtf, .html, .plainText,
            UTType(importedAs: "com.microsoft.word.doc"),
            UTType(importedAs: "org.openxmlformats.wordprocessingml.document")
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        
        if panel.runModal() == .OK {
            fileURL = panel.url
        }
    }
    
    /// Этап 5: конвертация одного файла (голова очереди). Очередь —
    /// enqueueConversion/processNextConversion по образцу хаба (HubView).
    private func startConversion() {
        guard let url = fileURL else { return }
        isConverting = true
        errorMessage = nil
        conversionResult = ""
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let md = try ConverterService.convert(url: url)
                
                // Этап 2: автосохранение в defaultSavePath БЕЗ force-unwrap (SPEC N-7).
                guard let saveFolder = SettingsStore.shared.defaultSaveFolderURL() else {
                    throw ConversionError.loadFailed
                }
                
                try FileManager.default.createDirectory(at: saveFolder, withIntermediateDirectories: true)
                
                let fileName = url.deletingPathExtension().appendingPathExtension("md").lastPathComponent
                var targetURL = saveFolder.appendingPathComponent(fileName)
                var counter = 1
                let baseName = url.deletingPathExtension().lastPathComponent
                while FileManager.default.fileExists(atPath: targetURL.path) {
                    targetURL = saveFolder.appendingPathComponent("\(baseName) (\(counter)).md")
                    counter += 1
                }
                
                try md.write(to: targetURL, atomically: true, encoding: .utf8)
                
                DispatchQueue.main.async {
                    // Открываем документ через AppState DuckMD
                    self.appState.openDocument(at: targetURL)
                    
                    // Окно конвертера закрываем только когда очередь пуста:
                    // при активном мультидропе остаток файлов не должен остаться
                    // в закрытом окне (Этап 5 — фикс потери файлов).
                    if self.dropQueue.isEmpty {
                        if let window = NSApp.windows.first(where: { $0.title == "Конвертер документов в MD" }) {
                            window.close()
                        }
                        
                        // Выводим главное окно DuckMD на передний план
                        if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title != "Конвертер документов в MD" && $0.title != "О DuckMD" && $0.canBecomeMain }) {
                            mainWindow.makeKeyAndOrderFront(nil)
                        }
                        NSApp.activate(ignoringOtherApps: true)
                    }
                    
                    self.fileURL = nil
                    self.conversionResult = ""
                    self.isConverting = false
                    self.processNextConversion()
                }
            } catch {
                Diag.export.error("Ошибка конвертации: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), srcExt=\(url.pathExtension.lowercased(), privacy: .public)")
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isConverting = false
                    self.processNextConversion()
                }
            }
        }
    }

    // MARK: - Этап 5: последовательная очередь drop (образец — хаб)

    /// Подача дроп-файлов в очередь с защитой от дубликатов; обработка —
    /// строго по одному (processNextConversion), мультидроп не теряет файлы.
    private func enqueueConversion(_ urls: [URL]) {
        let newOnes = urls.filter { url in !dropQueue.contains(url) && url != fileURL }
        dropQueue.append(contentsOf: newOnes)
        processNextConversion()
    }

    /// Берёт следующий файл из очереди, если сейчас ничего не конвертируется.
    private func processNextConversion() {
        guard !isConverting, !dropQueue.isEmpty, let next = dropQueue.first else { return }
        dropQueue.removeFirst()
        fileURL = next
        startConversion()
    }
    
    private func saveMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.markdownDoc]
        panel.nameFieldStringValue = fileURL?.deletingPathExtension().appendingPathExtension("md").lastPathComponent ?? "document.md"
        
        if panel.runModal() == .OK, let saveURL = panel.url {
            do {
                try conversionResult.write(to: saveURL, atomically: true, encoding: .utf8)
                Diag.export.info("Результат конвертации сохранён, bytes=\(conversionResult.utf8.count, privacy: .public)")
            } catch {
                Diag.export.error("Ошибка сохранения результата конвертации: type=\(String(describing: type(of: error)), privacy: .public), detail=\(String(describing: error), privacy: .private), path=\(saveURL.path, privacy: .private)")
            }
        }
    }
    
    private func openInEditor() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileURL?.deletingPathExtension().appendingPathExtension("md").lastPathComponent ?? "converted-\(Int(Date().timeIntervalSince1970)).md")
            
        do {
            try conversionResult.write(to: tempURL, atomically: true, encoding: .utf8)
            appState.openDocument(at: tempURL)
            // Закрываем окно конвертера
            if let window = NSApp.windows.first(where: { $0.title == "Конвертер документов в MD" }) {
                window.close()
            }
            // Выводим главное окно DuckMD на передний план
            if let mainWindow = NSApp.windows.first(where: { !($0 is NSPanel) && $0.title != "Конвертер документов в MD" && $0.title != "О DuckMD" && $0.canBecomeMain }) {
                mainWindow.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        } catch {
            errorMessage = "Не удалось открыть файл в редакторе"
        }
    }
    
    /// Этап 5: дроп подаёт файлы в последовательную очередь (раньше каждый
    /// URL сразу запускал startConversion — мультидроп терял файлы).
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            DocumentDropHelper.extractURL(from: provider) { url in
                DispatchQueue.main.async {
                    self.enqueueConversion([url])
                }
            }
        }
        return true
    }
}
