import SwiftUI
import AppKit

/// Нативный AppKit View для разделителя сплит-режима с гарантированным системным курсором resizeLeftRight.
/// Использование addCursorRect предотвращает мерцание и конфликты со стеком курсоров WebKit и NSTextView.
final class SplitDividerTrackingView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override var isOpaque: Bool { false }
}

struct SplitDividerCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> SplitDividerTrackingView {
        SplitDividerTrackingView()
    }

    func updateNSView(_ nsView: SplitDividerTrackingView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

/// Нативный AppKit View для ползунка скролла, гарантирующий отображение стандартной стрелки курсора (.arrow)
final class ScrollThumbTrackingView: NSView {
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }

    override var isOpaque: Bool { false }
}

struct ScrollThumbCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollThumbTrackingView {
        ScrollThumbTrackingView()
    }

    func updateNSView(_ nsView: ScrollThumbTrackingView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}
