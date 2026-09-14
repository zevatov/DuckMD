import SwiftUI

/// Вью для окна «О программе». Показывает логотип-утку и версию DuckMD.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 20) {
            DuckLogo(size: 120)
                .padding(.top, 24)
            
            VStack(spacing: 8) {
                Text("DuckMD")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                
                Text("Версия \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("© 2026 DuckMD. Все права защищены.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .opacity(0.7)
                .padding(.bottom, 24)
        }
        .frame(width: 320, height: 280)
        .background(VisualEffectView(material: .hudWindow, blendingMode: .behindWindow))
    }
}

/// Вспомогательное вью для эффектов размытия macOS (Liquid Glass).
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
