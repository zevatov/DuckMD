import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Document Drop Helper (R4)

/// Общий обработчик drag-and-drop файлов (R4, дедупликация handleDrop
/// из ContentView / HubView / ConverterView).
/// Markdown-файлы (.md/.markdown) открываются в редакторе через appState,
/// остальные передаются обработчику вызывающей стороны.
enum DocumentDropHelper {
    /// Является ли файл Markdown-документом по расширению.
    static func isMarkdown(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }

    /// Надёжное извлечение URL из NSItemProvider с поддержкой loadObject и fallback на loadItem
    static func extractURL(from provider: NSItemProvider, completion: @escaping (URL) -> Void) {
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    completion(url)
                } else {
                    fallbackLoadItem(from: provider, completion: completion)
                }
            }
        } else {
            fallbackLoadItem(from: provider, completion: completion)
        }
    }

    private static func fallbackLoadItem(from provider: NSItemProvider, completion: @escaping (URL) -> Void) {
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            if let url = item as? URL {
                completion(url)
            } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                completion(url)
            }
        }
    }

    /// Стандартный drop: md → редактор, остальное → конвертер (через pendingConversionURL).
    /// `openConverter` — способ открытия окна конвертера, различается у вызывающих
    /// (ContentView ищет окно по title, HubView использует openWindow(id:)).
    static func handleStandardDrop(
        providers: [NSItemProvider],
        appState: AppState,
        openConverter: @escaping () -> Void
    ) -> Bool {
        for provider in providers {
            extractURL(from: provider) { url in
                DispatchQueue.main.async {
                    if isMarkdown(url) {
                        appState.openDocument(at: url)
                    } else {
                        appState.pendingConversionURL = url
                        openConverter()
                    }
                }
            }
        }
        return true
    }
}
