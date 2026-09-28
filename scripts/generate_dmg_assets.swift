import Foundation
import AppKit
import CoreGraphics

let currentDir = FileManager.default.currentDirectoryPath
let bgPath = "\(currentDir)/dmg_background.png"
let previewMockupPath = "\(currentDir)/scripts/dmg_assets/dmg_preview_mockup.png"
let githubIconPath = "\(currentDir)/scripts/dmg_assets/github_white.png"
let telegramIconPath = "\(currentDir)/scripts/dmg_assets/telegram_white.png"
let appIconPath = "\(currentDir)/scripts/dmg_assets/app_icon.png"

let bgSize = NSSize(width: 660, height: 480)
let scale: CGFloat = 2.0 // Retina 2x (1320x960)

func createRetinaBitmap(size: NSSize) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale),
        pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .calibratedRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = size
    return rep
}

// ----------------------------------------------------
// 1. GENERATE BACKGROUND IMAGE (dmg_background.png)
// ----------------------------------------------------
let bgRep = createRetinaBitmap(size: bgSize)
NSGraphicsContext.saveGraphicsState()
let bgContext = NSGraphicsContext(bitmapImageRep: bgRep)!
NSGraphicsContext.current = bgContext

// Brand gradient: Amber Gold to Warm Orange at -45 degrees
let brandStart = NSColor(red: 250/255, green: 175/255, blue: 18/255, alpha: 1.0)
let brandEnd = NSColor(red: 240/255, green: 90/255, blue: 30/255, alpha: 1.0)
let gradient = NSGradient(starting: brandStart, ending: brandEnd)
gradient?.draw(in: NSRect(origin: .zero, size: bgSize), angle: -45)

// Decorative glyphs & crosses (subtle white)
let infoColor = NSColor.white.withAlphaComponent(0.10)
let infoAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 18, weight: .bold),
    .foregroundColor: infoColor
]

func drawCross(at point: NSPoint) {
    let crossPath = NSBezierPath()
    crossPath.move(to: NSPoint(x: point.x - 5, y: point.y))
    crossPath.line(to: NSPoint(x: point.x + 5, y: point.y))
    crossPath.move(to: NSPoint(x: point.x, y: point.y - 5))
    crossPath.line(to: NSPoint(x: point.x, y: point.y + 5))
    crossPath.lineWidth = 1.5
    NSColor.white.withAlphaComponent(0.14).setStroke()
    crossPath.stroke()
}

drawCross(at: NSPoint(x: 30, y: 30))
drawCross(at: NSPoint(x: bgSize.width - 30, y: 30))
drawCross(at: NSPoint(x: 30, y: bgSize.height - 30))
drawCross(at: NSPoint(x: bgSize.width - 30, y: bgSize.height - 30))

"#".draw(at: NSPoint(x: 75, y: 395), withAttributes: infoAttrs)
"**".draw(at: NSPoint(x: bgSize.width - 115, y: 395), withAttributes: infoAttrs)
">".draw(at: NSPoint(x: 280, y: 395), withAttributes: infoAttrs)

let letterAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 14, weight: .medium),
    .foregroundColor: infoColor
]
"[x]".draw(at: NSPoint(x: 95, y: 102), withAttributes: letterAttrs)
"</>".draw(at: NSPoint(x: bgSize.width - 115, y: 102), withAttributes: letterAttrs)
"MD".draw(at: NSPoint(x: bgSize.width / 2 - 12, y: 98), withAttributes: letterAttrs)

// Translucent card for drag-and-drop
let panelRect = NSRect(x: 50, y: 135, width: 560, height: 210)
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
NSColor.white.withAlphaComponent(0.08).set()
panelPath.fill()
NSColor.white.withAlphaComponent(0.16).set()
panelPath.lineWidth = 1.5
panelPath.stroke()

// Solid elegant chevron arrow (centered at X=330, Y=240 in AppKit)
let arrowPath = NSBezierPath()
let arrowY: CGFloat = 240
let arrowH: CGFloat = 16
let arrowTipW: CGFloat = 24
let arrowBodyW: CGFloat = 36
let arrowStart: CGFloat = 330 - (arrowBodyW + arrowTipW) / 2

arrowPath.move(to: NSPoint(x: arrowStart, y: arrowY - arrowH / 2))
arrowPath.line(to: NSPoint(x: arrowStart + arrowBodyW, y: arrowY - arrowH / 2))
arrowPath.line(to: NSPoint(x: arrowStart + arrowBodyW, y: arrowY - arrowH))
arrowPath.line(to: NSPoint(x: arrowStart + arrowBodyW + arrowTipW, y: arrowY))
arrowPath.line(to: NSPoint(x: arrowStart + arrowBodyW, y: arrowY + arrowH))
arrowPath.line(to: NSPoint(x: arrowStart + arrowBodyW, y: arrowY + arrowH / 2))
arrowPath.line(to: NSPoint(x: arrowStart, y: arrowY + arrowH / 2))
arrowPath.close()

NSColor.white.withAlphaComponent(0.40).set()
arrowPath.fill()

// Header: Title "DuckMD" & Subtitle
let titleText = "DuckMD"
let titleFont = NSFont.systemFont(ofSize: 34, weight: .bold)
let titleAttrs: [NSAttributedString.Key: Any] = [
    .font: titleFont,
    .foregroundColor: NSColor.white
]
let titleSize = titleText.size(withAttributes: titleAttrs)
titleText.draw(at: NSPoint(x: (bgSize.width - titleSize.width) / 2, y: bgSize.height - 62), withAttributes: titleAttrs)

let subtitleText = "Перетащите DuckMD в Applications для установки"
let subtitleFont = NSFont.systemFont(ofSize: 13, weight: .medium)
let subtitleAttrs: [NSAttributedString.Key: Any] = [
    .font: subtitleFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.88)
]
let subtitleSize = subtitleText.size(withAttributes: subtitleAttrs)
subtitleText.draw(at: NSPoint(x: (bgSize.width - subtitleSize.width) / 2, y: bgSize.height - 88), withAttributes: subtitleAttrs)

// Bottom links: GitHub & Telegram
let linkFont = NSFont.systemFont(ofSize: 12, weight: .medium)
let linkAttrs: [NSAttributedString.Key: Any] = [
    .font: linkFont,
    .foregroundColor: NSColor.white.withAlphaComponent(0.92)
]
let logoSize = NSSize(width: 18, height: 18)
let bottomY: CGFloat = 68

// GitHub: logo + github.com/zevatov/DuckMD
if let ghIcon = NSImage(contentsOfFile: githubIconPath) {
    ghIcon.draw(in: NSRect(x: 50, y: bottomY - 1, width: logoSize.width, height: logoSize.height), from: .zero, operation: .sourceOver, fraction: 0.92)
}
let githubText = "github.com/zevatov/DuckMD"
githubText.draw(at: NSPoint(x: 74, y: bottomY), withAttributes: linkAttrs)

// Telegram: logo + t.me/vostr_dev
let telegramText = "t.me/vostr_dev"
let tgTextSize = telegramText.size(withAttributes: linkAttrs)
let tgRightPadding: CGFloat = 50
let tgTextX = bgSize.width - tgTextSize.width - tgRightPadding
let tgLogoX = tgTextX - 24

if let tgIcon = NSImage(contentsOfFile: telegramIconPath) {
    tgIcon.draw(in: NSRect(x: tgLogoX, y: bottomY - 1, width: logoSize.width, height: logoSize.height), from: .zero, operation: .sourceOver, fraction: 0.92)
}
telegramText.draw(at: NSPoint(x: tgTextX, y: bottomY), withAttributes: linkAttrs)

NSGraphicsContext.restoreGraphicsState()

guard let bgPngData = bgRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode background PNG")
}
try bgPngData.write(to: URL(fileURLWithPath: bgPath))
print("Saved background image to \(bgPath)")

// ----------------------------------------------------
// 2. GENERATE MOCKUP OF OPENED DMG WINDOW (Finder view)
// ----------------------------------------------------
let titleBarHeight: CGFloat = 38
let windowSize = NSSize(width: bgSize.width, height: bgSize.height + titleBarHeight)
let mockupRep = createRetinaBitmap(size: windowSize)

NSGraphicsContext.saveGraphicsState()
let mockupContext = NSGraphicsContext(bitmapImageRep: mockupRep)!
NSGraphicsContext.current = mockupContext

// Window rounded background clip
let windowRect = NSRect(origin: .zero, size: windowSize)
let windowClip = NSBezierPath(roundedRect: windowRect, xRadius: 12, yRadius: 12)
windowClip.addClip()

// Draw the background image in the content area (y = 0..480)
let bgImg = NSImage(data: bgPngData)!
bgImg.draw(in: NSRect(x: 0, y: 0, width: bgSize.width, height: bgSize.height))

// Draw macOS window Title Bar (y = 480..518)
let titleBarRect = NSRect(x: 0, y: bgSize.height, width: bgSize.width, height: titleBarHeight)
NSColor(red: 0.15, green: 0.15, blue: 0.16, alpha: 1.0).set()
titleBarRect.fill()

// Title bar traffic lights
let trafficY = bgSize.height + (titleBarHeight - 12) / 2
let closeDot = NSBezierPath(ovalIn: NSRect(x: 14, y: trafficY, width: 12, height: 12))
NSColor(red: 1.0, green: 0.36, blue: 0.34, alpha: 1.0).set()
closeDot.fill()

let minDot = NSBezierPath(ovalIn: NSRect(x: 34, y: trafficY, width: 12, height: 12))
NSColor(red: 1.0, green: 0.74, blue: 0.18, alpha: 1.0).set()
minDot.fill()

let zoomDot = NSBezierPath(ovalIn: NSRect(x: 54, y: trafficY, width: 12, height: 12))
NSColor(red: 0.16, green: 0.79, blue: 0.29, alpha: 1.0).set()
zoomDot.fill()

// Window Title
let winTitle = "DuckMD"
let winTitleAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
    .foregroundColor: NSColor.white.withAlphaComponent(0.85)
]
let winTitleSize = winTitle.size(withAttributes: winTitleAttrs)
winTitle.draw(at: NSPoint(x: (bgSize.width - winTitleSize.width) / 2, y: bgSize.height + (titleBarHeight - winTitleSize.height) / 2), withAttributes: winTitleAttrs)

// Draw Finder items inside the window!
let iconPixelSize: CGFloat = 110
let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 12, weight: .medium),
    .foregroundColor: NSColor.white
]

// Left item: DuckMD.app
if let appIcon = NSImage(contentsOfFile: appIconPath) {
    let appRect = NSRect(x: 180 - iconPixelSize / 2, y: 240 - iconPixelSize / 2 + 10, width: iconPixelSize, height: iconPixelSize)
    appIcon.draw(in: appRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    
    let label = "DuckMD"
    let lSize = label.size(withAttributes: labelAttrs)
    let labelRect = NSRect(x: 180 - lSize.width / 2 - 6, y: 240 - iconPixelSize / 2 - 12, width: lSize.width + 12, height: lSize.height + 2)
    NSColor.black.withAlphaComponent(0.4).set()
    NSBezierPath(roundedRect: labelRect, xRadius: 4, yRadius: 4).fill()
    label.draw(at: NSPoint(x: 180 - lSize.width / 2, y: 240 - iconPixelSize / 2 - 11), withAttributes: labelAttrs)
}

// Right item: Applications folder
let appsFolderIcon = NSWorkspace.shared.icon(forFile: "/Applications")
let appsRect = NSRect(x: 480 - iconPixelSize / 2, y: 240 - iconPixelSize / 2 + 10, width: iconPixelSize, height: iconPixelSize)
appsFolderIcon.draw(in: appsRect, from: .zero, operation: .sourceOver, fraction: 1.0)

let appsLabel = "Applications"
let alSize = appsLabel.size(withAttributes: labelAttrs)
let appsLabelRect = NSRect(x: 480 - alSize.width / 2 - 6, y: 240 - iconPixelSize / 2 - 12, width: alSize.width + 12, height: alSize.height + 2)
NSColor.black.withAlphaComponent(0.4).set()
NSBezierPath(roundedRect: appsLabelRect, xRadius: 4, yRadius: 4).fill()
appsLabel.draw(at: NSPoint(x: 480 - alSize.width / 2, y: 240 - iconPixelSize / 2 - 11), withAttributes: labelAttrs)

NSGraphicsContext.restoreGraphicsState()

guard let mockupPngData = mockupRep.representation(using: .png, properties: [:]) else {
    fatalError("Failed to encode mockup PNG")
}
try mockupPngData.write(to: URL(fileURLWithPath: previewMockupPath))
print("Saved preview mockup to \(previewMockupPath)")
