import SwiftUI

/// Гранёная low-poly жёлтая уточка-маскот DuckMD.
struct DuckLogo: View {
    var size: CGFloat = 28
    /// Флаг для совместимости вызовов на тёмном фоне
    var onDark: Bool = false

    var body: some View {
        Image("DuckLogo")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityLabel(Text("DuckMD"))
    }
}

#Preview {
    VStack(spacing: 24) {
        DuckLogo(size: 64)
        DuckLogo(size: 32, onDark: true)
            .padding(12)
            .background(Color.black.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    .padding()
}

