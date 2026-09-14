import SwiftUI
import AppKit

/// Компонент отображения названия документа:
/// - Если текст помещается — отображается статично по ширине текста.
/// - Если длиннее — правый край плавно затухает градиентом (без троеточия).
/// - При наведении мыши плавно прокручивается до конца («пинг-понг» с паузой 1 сек),
///   а при уходе мыши плавно возвращается в исходное положение.
/// - Поддерживает как фиксированный maxWidth, так и адаптивный режим (maxWidth == nil)
///   с автоматическим заполнением ширины контейнера.
struct MarqueeText: View {
    let text: String
    let font: Font
    let fontWeight: Font.Weight
    let isHovered: Bool
    var maxWidth: CGFloat? = nil

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>? = nil

    private var effectiveWidth: CGFloat {
        if let fixed = maxWidth, fixed > 0 {
            return fixed
        }
        return containerWidth > 0 ? containerWidth : textWidth
    }

    var body: some View {
        Group {
            if let fixed = maxWidth, fixed > 0 {
                marqueeContent(width: min(textWidth > 0 ? textWidth : fixed, fixed))
            } else {
                GeometryReader { geo in
                    marqueeContent(width: geo.size.width)
                        .preference(key: ContainerWidthPreferenceKey.self, value: geo.size.width)
                }
                .frame(height: 20)
                .onPreferenceChange(ContainerWidthPreferenceKey.self) { newWidth in
                    if containerWidth != newWidth {
                        containerWidth = newWidth
                    }
                }
            }
        }
        .clipped()
        .onPreferenceChange(TextWidthPreferenceKey.self) { newWidth in
            textWidth = newWidth
        }
        .onChange(of: isHovered) { _, hovering in
            handleHoverChange(hovering: hovering)
        }
        .onChange(of: text) { _, _ in
            resetOffset()
        }
    }

    @ViewBuilder
    private func marqueeContent(width: CGFloat) -> some View {
        let overflowing = textWidth > width && width > 0
        ZStack(alignment: .leading) {
            // Невидимый измеритель ширины текста
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { textProxy in
                        Color.clear.preference(key: TextWidthPreferenceKey.self, value: textProxy.size.width)
                    }
                )
                .hidden()

            // Отображаемый текст
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .lineLimit(1)
                .fixedSize()
                .offset(x: offset)
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask {
            if overflowing {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.86),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Rectangle().fill(Color.black)
            }
        }
    }

    private func handleHoverChange(hovering: Bool) {
        animationTask?.cancel()
        let width = effectiveWidth
        let overflowing = textWidth > width && width > 0

        if hovering && overflowing {
            let maxOffset = textWidth - width + 14
            let speed: Double = 36 // pt / sec
            let duration = max(0.8, Double(maxOffset) / speed)

            animationTask = Task { @MainActor in
                while !Task.isCancelled {
                    // Пауза 0.4 сек перед началом движения
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    if Task.isCancelled { break }

                    // Движение до конца скрытого текста
                    withAnimation(.easeInOut(duration: duration)) {
                        offset = -maxOffset
                    }
                    try? await Task.sleep(nanoseconds: UInt64((duration + 1.0) * 1_000_000_000))
                    if Task.isCancelled { break }

                    // Плавное возвращение назад
                    withAnimation(.easeInOut(duration: duration * 0.75)) {
                        offset = 0
                    }
                    try? await Task.sleep(nanoseconds: UInt64((duration * 0.75 + 1.2) * 1_000_000_000))
                }
            }
        } else {
            resetOffset()
        }
    }

    private func resetOffset() {
        animationTask?.cancel()
        withAnimation(.easeInOut(duration: 0.25)) {
            offset = 0
        }
    }
}

private struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct ContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
