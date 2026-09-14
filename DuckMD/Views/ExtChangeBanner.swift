import SwiftUI

/// Баннер уведомления о внешнем изменении файла.
struct ExtChangeBanner: View {
    let secondsRemaining: Int
    let hasLocalEdits: Bool
    let onApply: () -> Void
    let onCancel: () -> Void
    let onKeepMine: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.orange)
                .font(.system(size: 16, weight: .bold))
            
            if hasLocalEdits {
                Text("Файл изменён внешне, но у вас есть несохранённые правки.")
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                Button("Применить внешние") {
                    onApply()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
                
                Button("Оставить мои") {
                    onKeepMine()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Text("Файл изменён внешне. Обновление через \(secondsRemaining) с...")
                    .font(.system(size: 13, weight: .medium))
                
                Spacer()
                
                Button("Отменить") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}
