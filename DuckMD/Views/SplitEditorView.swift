import SwiftUI
import AppKit

/// Split Mode: код слева, WKWebView рендер справа.
/// Оснащен единой центральной рельсой скролла с нативным ползунком,
/// системным курсором resizeLeftRight и заморозкой рендера с иконками режимов при перетаскивании.
struct SplitEditorView: View {
    @ObservedObject var document: MarkdownDocument
    /// Этап 1.3: проброс во вложенный CodeEditorView — очередь внешних текстов
    /// при фокусе редактора (см. ContentView.queueExternalUpdate).
    var onPendingExternalText: ((String, String) -> Void)? = nil
    @EnvironmentObject private var appState: AppState
    @Environment(\.undoManager) private var undoManager

    @ObservedObject private var settings = SettingsStore.shared
    
    /// Флаг перетаскивания разделителя панелей
    @State private var isDraggingSplitter = false
    /// Локальное отношение ширины во время drag (не триггерит ререндер внешних моделей)
    @State private var liveDragRatio: CGFloat? = nil

    /// Источник ведущего скролла для полного устранения дребезга и циклического эхо
    enum ScrollLeader {
        case idle
        case editor
        case preview
        case thumb
    }
    @State private var scrollLeader: ScrollLeader = .idle
    @State private var leaderResetTimer: Timer? = nil

    /// Состояние единого ползунка скролла
    @State private var unifiedScrollFraction: CGFloat = 0
    @State private var isThumbDragging = false
    @State private var isThumbHovered = false
    @State private var isScrollActive = false
    @State private var idleTimer: Timer? = nil

    /// Целевая дробь для ПРЕВЬЮ (устанавливается редактором или ползунком)
    @State private var previewTarget: CGFloat = 0
    /// Целевая позиция для ПРЕВЬЮ (строка, смещение, дробь)
    @State private var previewTargetPosition: (line: Int, offset: CGFloat, fraction: CGFloat)? = nil
    /// Целевая дробь для РЕДАКТОРА (устанавливается превью или ползунком)
    @State private var editorTarget: CGFloat = 0
    /// Целевая позиция для РЕДАКТОРА (строка, следующая строка, смещение, дробь)
    @State private var editorTargetPosition: (line: Int, nextLine: Int?, offset: CGFloat, fraction: CGFloat)? = nil
    /// Активная строка для синхронного выделения
    @State private var activeLine: Int = 1
    /// Активная колонка для выделения ячейки
    @State private var activeCol: Int? = nil

    /// Активный логический блок Markdown для подсветки в редакторе кода
    private var activeBlockRange: ClosedRange<Int>? {
        guard activeLine >= 1 else { return nil }
        if let block = document.parsedBlocks.first(where: {
            let start = $0.sourceLine ?? -1
            let end = $0.endLine ?? start
            return activeLine >= start && activeLine <= end
        }) {
            let start = block.sourceLine ?? activeLine
            let end = block.endLine ?? start
            return start...end
        }
        return activeLine...activeLine
    }

    var body: some View {
        GeometryReader { geometry in
            let currentRatio = liveDragRatio ?? appState.splitRatio
            HStack(spacing: 0) {
                // Левая панель: Редактор кода (с заморозкой при перетаскивании разделителя)
                ZStack {
                    CodeEditorView(
                        text: $document.text,
                        scrollFraction: editorTarget,
                        scrollPosition: editorTargetPosition,
                        syncScroll: settings.syncScroll,
                        activeLine: activeLine,
                        highlightedLineRange: activeBlockRange,
                        onScrollFractionChanged: { fraction in
                            guard settings.syncScroll else { return }
                            guard scrollLeader != .preview && scrollLeader != .thumb else { return }
                            setLeader(.editor)
                            unifiedScrollFraction = fraction
                            previewTarget = fraction
                            notifyScrollActivity()
                        },
                        onScrollPositionChanged: { line, offset, fraction in
                            guard settings.syncScroll else { return }
                            guard scrollLeader != .preview && scrollLeader != .thumb else { return }
                            setLeader(.editor)
                            previewTargetPosition = (line, offset, fraction)
                            unifiedScrollFraction = fraction
                            previewTarget = fraction
                            notifyScrollActivity()
                        },
                        onCursorLineChanged: { line, col in
                            activeLine = line
                            activeCol = col
                        },
                        onPendingExternalText: onPendingExternalText
                    )
                    .background(Color(nsColor: .textBackgroundColor))

                    if isDraggingSplitter {
                        ZStack {
                            Color(nsColor: .textBackgroundColor).opacity(0.85)
                            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            VStack(spacing: 10) {
                                Image(systemName: "chevron.left.forwardslash.chevron.right")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Код")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(width: max(140, geometry.size.width * currentRatio))

                // Центральная рельса скролла и разделитель панелей
                centralScrollRail(geometry: geometry)

                // Правая панель: WKWebView рендерер
                // Во время isDraggingSplitter WebPreviewView ПОЛНОСТЬЮ убран из иерархии:
                // WebKit не получает событий изменения размера и не делает фонового reflow!
                ZStack {
                    if isDraggingSplitter {
                        ZStack {
                            Color(nsColor: .windowBackgroundColor).opacity(0.9)
                            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
                            VStack(spacing: 10) {
                                Image(systemName: "doc.richtext")
                                    .font(.system(size: 32, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text("Просмотр")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .transition(.opacity)
                    } else if document.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ScrollView {
                            EmptyStateView()
                                .padding(.vertical, 60)
                                .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        WebPreviewView.makeStandard(
                            document: document,
                            hideScrollbar: true, // Скрываем правый скроллбар: активна центральная рельса
                            scrollFraction: settings.syncScroll ? previewTarget : nil,
                            scrollPosition: settings.syncScroll ? previewTargetPosition : nil,
                            activeLine: activeLine,
                            activeCol: activeCol,
                            onScroll: settings.syncScroll ? { fraction in
                                guard scrollLeader != .editor && scrollLeader != .thumb else { return }
                                setLeader(.preview)
                                unifiedScrollFraction = fraction
                                editorTarget = fraction
                                notifyScrollActivity()
                            } : nil,
                            onScrollPosition: settings.syncScroll ? { line, nextLine, offset, fraction in
                                guard scrollLeader != .editor && scrollLeader != .thumb else { return }
                                setLeader(.preview)
                                unifiedScrollFraction = fraction
                                editorTargetPosition = (line, nextLine, offset, fraction)
                                editorTarget = fraction
                                notifyScrollActivity()
                            } : nil,
                            onElementClicked: { line in
                                activeLine = line
                                activeCol = nil
                            },
                            onElementEdited: { line, newText in
                                activeLine = line
                                activeCol = nil
                                if let block = document.parsedBlocks.first(where: { $0.sourceLine == line }),
                                   let endLine = block.endLine {
                                    let updatedText = RenderEditParser.applyEdit(startLine: line, endLine: endLine, newText: newText, to: document.text)
                                    updateText(updatedText)
                                }
                            },
                            onTableCellEdited: { line, row, col, newText in
                                let updatedText = RenderEditParser.applyTableCellEdit(tableLine: line, row: row, col: col, newText: newText, to: document.text)
                                updateText(updatedText)
                            },
                            onCheckboxToggled: { line, checked in
                                guard line >= 1,
                                      document.parsedBlocks.contains(where: { $0.sourceLine == line }),
                                      let updatedLines = RenderEditParser.applyCheckboxToggle(lines: document.text.components(separatedBy: "\n"), line: line, checked: checked) else { return }
                                updateText(updatedLines.joined(separator: "\n"))
                            },
                            updateText: updateText
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .coordinateSpace(name: "splitContainer")
        }
    }

    // MARK: - Central Scroll Rail & Divider

    @ViewBuilder
    private func centralScrollRail(geometry: GeometryProxy) -> some View {
        let totalHeight = geometry.size.height
        let thumbHeight: CGFloat = max(36, min(120, totalHeight * 0.18))
        let availableTrack = max(1, totalHeight - thumbHeight - 8)
        let thumbY = 4 + min(max(0, unifiedScrollFraction), 1.0) * availableTrack

        let isBright = isThumbDragging || isThumbHovered || isScrollActive
        let thumbOpacity = isBright ? 0.65 : 0.25
        let thumbWidth: CGFloat = (isThumbDragging || isThumbHovered) ? 6 : 4

        ZStack {
            // 1. Нативный AppKit курсор resizeLeftRight и область горизонтального ресайза
            SplitDividerCursorView()
                .frame(width: 14)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2, coordinateSpace: .named("splitContainer"))
                        .onChanged { value in
                            guard !isThumbDragging else { return }
                            if !isDraggingSplitter {
                                isDraggingSplitter = true
                            }
                            let newRatio = value.location.x / geometry.size.width
                            liveDragRatio = min(max(newRatio, 0.2), 0.8)
                        }
                        .onEnded { _ in
                            if let finalRatio = liveDragRatio {
                                appState.splitRatio = finalRatio
                            }
                            liveDragRatio = nil
                            isDraggingSplitter = false
                        }
                )

            // 2. Тонкая вертикальная рельса
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1.5)

            // 3. Единый ползунок прокрутки (Scroll Thumb)
            ZStack {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.primary.opacity(thumbOpacity))
                ScrollThumbCursorView()
            }
            .frame(width: thumbWidth, height: thumbHeight)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .position(x: 7, y: thumbY + thumbHeight / 2)
            .animation(.easeInOut(duration: 0.15), value: isBright)
                .onHover { inside in
                    isThumbHovered = inside
                    if inside {
                        notifyScrollActivity()
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("splitContainer"))
                        .onChanged { value in
                            isThumbDragging = true
                            setLeader(.thumb)
                            notifyScrollActivity()
                            let dragY = value.location.y - (thumbHeight / 2)
                            let newFraction = min(max(0, (dragY - 4) / availableTrack), 1.0)
                            unifiedScrollFraction = newFraction
                            // Очищаем точечные позиции строк для прямого синхронного скролла обеих областей
                            previewTargetPosition = nil
                            editorTargetPosition = nil
                            previewTarget = newFraction
                            editorTarget = newFraction
                        }
                        .onEnded { _ in
                            isThumbDragging = false
                            notifyScrollActivity()
                            setLeader(.idle)
                        }
                )
        }
        .frame(width: 14)
    }

    private func setLeader(_ leader: ScrollLeader) {
        scrollLeader = leader
        leaderResetTimer?.invalidate()
        let timeout: TimeInterval = (leader == .editor) ? 0.45 : 0.25
        leaderResetTimer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { _ in
            scrollLeader = .idle
        }
    }

    private func notifyScrollActivity() {
        isScrollActive = true
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { _ in
            isScrollActive = false
        }
    }

    private func updateText(_ newText: String) {
        TextEditApplier.apply(newText, to: document, undoManager: undoManager)
    }
}
