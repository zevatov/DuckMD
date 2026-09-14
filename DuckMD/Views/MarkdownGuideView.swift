import SwiftUI

// R6: MarkdownGuideView + EmptyStateView перенесены из ContentView.swift как есть.

// MARK: - Empty state

struct EmptyStateView: View {
    @State private var isWiggling = false

    var body: some View {
        VStack(spacing: 16) {
            DuckLogo(size: 72)
                .rotationEffect(.degrees(isWiggling ? 6 : -6))
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isWiggling)
                .onAppear {
                    isWiggling = true
                }
            Text("DuckMD")
                .font(.system(size: 28, weight: .bold, design: .rounded))
            Text("Открой .md файл или переключись в режим «Код» и начни печатать.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Markdown Guide View

/// Компактная Markdown шпаргалка в стиле macOS.
struct MarkdownGuideView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Заголовок
            HStack(spacing: 8) {
                Image(systemName: "book.pages")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("Markdown шпаргалка")
                    .font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    guideSection("Заголовки", examples: [
                        ("# Заголовок 1", "H1"),
                        ("## Заголовок 2", "H2"),
                        ("### Заголовок 3", "H3")
                    ])

                    guideSection("Форматирование", examples: [
                        ("**жирный**", "жирный текст"),
                        ("*курсив*", "выделенный текст"),
                        ("~~зачёркнутый~~", "зачёркнутый текст"),
                        ("`код`", "встроенный код")
                    ])

                    guideSection("Списки", examples: [
                        ("- маркированный", "элемент списка"),
                        ("1. нумерованный", "элемент с номером"),
                        ("- [ ] задача", "невыполненное дело"),
                        ("- [x] готово", "выполненная задача")
                    ])

                    guideSection("Ссылки и медиа", examples: [
                        ("[Текст ссылки](url)", "ссылка на веб-сайт"),
                        ("![Описание](url)", "встроенное изображение")
                    ])

                    guideSection("Блоки", examples: [
                        ("> цитата", "выделенная цитата"),
                        ("```\nкод\n```", "многострочный код"),
                        ("---", "горизонтальная линия")
                    ])

                    guideSection("Таблицы", examples: [
                        ("| A | B |\n|---|---|\n| 1 | 2 |", "простая таблица")
                    ])
                }
                .padding(16)
            }
        }
        .frame(width: 320, height: 450)
    }

    @ViewBuilder
    private func guideSection(_ title: String, examples: [(String, String)]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)

                ForEach(examples, id: \.0) { item in
                    HStack(alignment: .top) {
                        Text(item.0)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)

                        Spacer()

                        Text(item.1)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    if item.0 != examples.last?.0 {
                        Divider()
                            .opacity(0.4)
                    }
                }
            }
            .padding(6)
        }
    }
}
