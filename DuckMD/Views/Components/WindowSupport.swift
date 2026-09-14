import SwiftUI
import AppKit

// R6: WindowAccessor + WindowCloseInterceptor перенесены из ContentView.swift
// как есть — поведение не изменилось.

// MARK: - Window Accessor for macOS SwiftUI

struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            callback(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            callback(nsView.window)
        }
    }
}

// MARK: - Close Interceptor to show save dialog

class WindowCloseInterceptor: NSObject {
    weak var window: NSWindow?
    var isDirty: () -> Bool = { false }
    var onConfirmSave: () -> Void = {}

    func setup(for window: NSWindow) {
        self.window = window
        if let closeButton = window.standardWindowButton(.closeButton) {
            closeButton.target = self
            closeButton.action = #selector(handleClose(_:))
        }
    }

    @objc func handleClose(_ sender: Any?) {
        if isDirty() {
            let alert = NSAlert()
            alert.messageText = "В документе есть несохраненные изменения"
            alert.informativeText = "Хотите сохранить изменения перед закрытием?"
            alert.addButton(withTitle: "Сохранить")      // 1-я кнопка
            alert.addButton(withTitle: "Отмена")         // 2-я кнопка
            alert.addButton(withTitle: "Не сохранять")   // 3-я кнопка

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                onConfirmSave()
                window?.close()
            } else if response == .alertThirdButtonReturn {
                // Сбрасываем флаг "грязного" документа и закрываем
                // (Присвоим пустую функцию, чтоб при повторном вызове не срабатывал)
                self.isDirty = { false }
                window?.close()
            }
            // Для "Отмена" ничего не делаем (окно не закроется)
        } else {
            window?.close()
        }
    }
}
