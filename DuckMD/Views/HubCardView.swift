import SwiftUI

/// Вью карточки недавнего файла для отображения в сетке Хаба.
struct HubCardView: View {
    let file: RecentFile
    let onOpen: () -> Void
    let onRemove: () -> Void
    
    @State private var isHovered = false
    @State private var isPressed = false
    @State private var showInfoPopover = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: file.exists ? "doc.text" : "doc.text.fill")
                    .font(.system(size: 16))
                    .foregroundColor(file.exists ? .accentColor : .secondary)
                
                MarqueeText(
                    text: file.title,
                    font: .system(size: 14),
                    fontWeight: .semibold,
                    isHovered: isHovered
                )
                .foregroundColor(file.exists ? .primary : .secondary)
                .help(file.title)
                
                Spacer(minLength: 4)
                
                if !file.exists {
                    Text("не найден")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Button {
                        showInfoPopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(showInfoPopover ? .accentColor : .secondary)
                            .opacity(isHovered || showInfoPopover ? 1.0 : 0.5)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Сведения о файле и расположение")
                    .popover(isPresented: $showInfoPopover, arrowEdge: .top) {
                        fileInfoPopover
                    }
                }
            }
            
            Text(file.preview.isEmpty ? "Пустой документ" : file.preview)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .frame(minHeight: 42, alignment: .topLeading)
            
            Spacer(minLength: 4)
            
            Divider()
            
            HStack {
                Text("\(file.wordCount) сл")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatDate(file.lastOpened))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(file.exists ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(Color.gray.opacity(0.1)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered && file.exists ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(isHovered && file.exists ? 0.08 : 0.01), radius: isHovered ? 6 : 2, x: 0, y: 2)
        .scaleEffect(isPressed ? 0.98 : (isHovered && file.exists ? 1.02 : 1.0))
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.05), value: isPressed)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if file.exists {
                onOpen()
            }
        }
        .contextMenu {
            if file.exists {
                Button("Открыть") {
                    onOpen()
                }
                Button("Показать в Finder") {
                    NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
                }
            }
            Button("Удалить из недавних", role: .destructive) {
                onRemove()
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
    }

    private var fileInfoPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text")
                    .font(.system(size: 22))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.title)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(2)
                    Text("\(file.wordCount) слов · \(ByteCountFormatter.string(fromByteCount: file.fileSize, countStyle: .file))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Расположение:")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(file.url.deletingLastPathComponent().path)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Изменён:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(file.lastModified))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                HStack {
                    Text("Открыт:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatDate(file.lastOpened))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
                } label: {
                    Label("Показать в Finder", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button("Закрыть") {
                    showInfoPopover = false
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
