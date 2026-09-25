// Generates Resources/AppIcon.icns: `swift scripts/make-icon.swift`
import AppKit

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(pixels) / 1024
    // "Squircle" background with the standard macOS icon margin.
    let tile = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(red: 0.20, green: 0.36, blue: 0.95, alpha: 1),
                        NSColor(red: 0.45, green: 0.23, blue: 0.86, alpha: 1)])!.draw(in: shape, angle: -60)
    // Priority grid: left side column, highlighted center, two on the right.
    let inner = tile.insetBy(dx: 120 * s, dy: 150 * s)
    let gap = 26 * s, w = inner.width, h = inner.height
    let zones: [(CGRect, Bool)] = [
        (CGRect(x: inner.minX, y: inner.minY, width: w * 0.25 - gap / 2, height: h), false),
        (CGRect(x: inner.minX + w * 0.25 + gap / 2, y: inner.minY, width: w * 0.5 - gap, height: h), true),
        (CGRect(x: inner.minX + w * 0.75 + gap / 2, y: inner.minY + h / 2 + gap / 2, width: w * 0.25 - gap / 2, height: h / 2 - gap / 2), false),
        (CGRect(x: inner.minX + w * 0.75 + gap / 2, y: inner.minY, width: w * 0.25 - gap / 2, height: h / 2 - gap / 2), false),
    ]
    for (rect, highlighted) in zones {
        let path = NSBezierPath(roundedRect: rect, xRadius: 28 * s, yRadius: 28 * s)
        NSColor.white.withAlphaComponent(highlighted ? 0.95 : 0.35).setFill()
        path.fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(pixels: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(pixels: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "✓ \(output.path)" : "iconutil failed")
