import SwiftUI
import AppKit

/// Нативное поле поиска macOS на базе AppKit NSSearchField.
/// Использует системный roundedBezel с материалом Liquid Glass (vibrancy),
/// встроенную лупу, нативную кнопку очистки и системное кольцо фокуса.
/// Никаких кастомных фонов, рамок и таблеток.
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Поиск недавних..."

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.bezelStyle = .roundedBezel
        field.focusRingType = .default
        field.centersPlaceholder = false
        field.font = NSFont.systemFont(ofSize: 12)
        field.target = context.coordinator
        field.action = #selector(Coordinator.action(_:))
        field.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField

        init(_ parent: NativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        @objc func action(_ sender: NSSearchField) {
            parent.text = sender.stringValue
        }
    }
}
