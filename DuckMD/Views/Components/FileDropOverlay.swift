import AppKit
import SwiftUI

/// Оверлей drag-and-drop на весь прямоугольник хозяина.
/// Хит-тест выключен: цель сброса — уже существующий `onDrop`.
struct FileDropOverlay: View {
    /// Закрытый режим подписи. Свободная строка снаружи не принимается.
    enum Mode {
        case open
        case convert

        fileprivate var title: String {
            switch self {
            case .open:
                return "Отпустите, чтобы открыть"
            case .convert:
                return "Отпустите, чтобы конвертировать"
            }
        }
    }

    let mode: Mode

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.9)
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(.secondary)
                    .accessibilityHidden(true)
                Text(mode.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mode.title)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

extension View {
    /// Показ только при `isPresented` (состояние targeted). Скрытие без задержки.
    /// Анимация не выходит за пределы оверлея.
    func fileDropOverlay(isPresented: Bool, mode: FileDropOverlay.Mode) -> some View {
        modifier(FileDropOverlayModifier(isPresented: isPresented, mode: mode))
    }
}

private struct FileDropOverlayModifier: ViewModifier {
    var isPresented: Bool
    var mode: FileDropOverlay.Mode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                if isPresented {
                    FileDropOverlay(mode: mode)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .animation(.easeInOut(duration: reduceMotion ? 0 : 0.15), value: isPresented)
        }
    }
}
