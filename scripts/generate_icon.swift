import Foundation
import CoreGraphics
import ImageIO
import AppKit

// Генерация иконки приложения DuckMD (1024×1024 PNG) через Core Graphics.
// Запуск: swift scripts/generate_icon.swift

let size: CGFloat = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil,
                          width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: colorSpace,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Не удалось создать контекст")
}

// macOS standard squircle bounds: 824x824 at (100, 100), radius 185
let sqRect = CGRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 185
let sqPath = CGPath(roundedRect: sqRect, cornerWidth: radius, cornerHeight: radius, transform: nil)

// Тень под сквирклом
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 28, color: CGColor(gray: 0, alpha: 0.28))
ctx.addPath(sqPath)
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.fillPath()
ctx.restoreGState()

// Фон внутри сквиркла
ctx.saveGState()
ctx.addPath(sqPath)
ctx.clip()

// Тёплый градиент (слоновая кость / бумага)
let topColor = CGColor(red: 1.0, green: 0.992, blue: 0.973, alpha: 1.0)
let botColor = CGColor(red: 0.957, green: 0.929, blue: 0.871, alpha: 1.0)
let grad = CGGradient(colorsSpace: colorSpace, colors: [topColor, botColor] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

// Внутренний ободок для чёткости
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.5))
ctx.setLineWidth(2.5)
ctx.addPath(sqPath)
ctx.strokePath()
ctx.restoreGState()

// Загрузка low-poly уточки
let duckURL = URL(fileURLWithPath: "DuckMD/Assets.xcassets/DuckLogo.imageset/duck_logo.png")
guard let dataProvider = CGDataProvider(url: duckURL as CFURL),
      let duckImage = CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
    fatalError("Не удалось загрузить duck_logo.png")
}

// Позиционирование уточки внутри сквиркла
let duckTargetSize: CGFloat = 570
let duckRect = CGRect(x: (size - duckTargetSize) / 2, y: (size - duckTargetSize) / 2 + 10, width: duckTargetSize, height: duckTargetSize)

// Тень под уточкой
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 14, color: CGColor(red: 0.08, green: 0.06, blue: 0.02, alpha: 0.22))
ctx.draw(duckImage, in: duckRect)
ctx.restoreGState()

// Отрисовка самой уточки
ctx.draw(duckImage, in: duckRect)

// === Сохраняем PNG ===
guard let img = ctx.makeImage() else { fatalError("makeImage failed") }
let outURL = URL(fileURLWithPath: "DuckMD/Assets.xcassets/AppIcon.appiconset/icon_1024.png")
guard let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("CGImageDestinationCreateWithURL failed")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
print("✓ Иконка сохранена: \(outURL.path)")
