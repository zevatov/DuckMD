import SwiftUI
import AppKit

struct AppIconView: View {
    var isDark: Bool
    
    var body: some View {
        ZStack {
            // macOS standard squircle background
            RoundedRectangle(cornerRadius: 110, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: isDark ? [Color(white: 0.18), Color(white: 0.10)] : [Color(white: 0.98), Color(white: 0.90)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.black.opacity(0.2), radius: 15, y: 10)
            
            // The cute duck logo in the center
            DuckLogo(size: 280, onDark: isDark)
                .shadow(color: Color.black.opacity(0.15), radius: 8, y: 6)
        }
        .frame(width: 512, height: 512)
    }
}

enum AppIconHelper {
    static func renderViewToImage<V: View>(_ view: V, size: NSSize) -> NSImage? {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        
        guard let bitmapRep = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            return nil
        }
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmapRep)
        
        let image = NSImage(size: size)
        image.addRepresentation(bitmapRep)
        return image
    }
    
    static func updateDockIcon(forTheme theme: ThemeMode) {
        DispatchQueue.main.async {
            let isDark: Bool
            switch theme {
            case .system:
                isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            case .light:
                isDark = false
            case .dark:
                isDark = true
            }
            
            let iconView = AppIconView(isDark: isDark)
            if let image = renderViewToImage(iconView, size: NSSize(width: 512, height: 512)) {
                NSApp.applicationIconImage = image
            }
        }
    }
}
