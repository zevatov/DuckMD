import SwiftUI

// MARK: - Text Edit Applier (R4)

/// Дедупликация `updateText(_:)` (R4): регистрация undo + присвоение текста документу.
/// Ранее одинаковая функция копировалась в ContentView и SplitEditorView.
enum TextEditApplier {
    /// Применяет новый текст к документу с регистрацией undo в переданном UndoManager.
    /// Замыкание получает себя же для рекурсивной регистрации обратного хода —
    /// поведение идентично прежним локальным `updateText`.
    static func apply(
        _ newText: String,
        to document: MarkdownDocument,
        undoManager: UndoManager?
    ) {
        let oldText = document.text
        guard oldText != newText else { return }
        undoManager?.registerUndo(withTarget: document) { target in
            self.apply(oldText, to: target, undoManager: undoManager)
        }
        document.text = newText
    }
}
