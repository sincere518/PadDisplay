import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor.systemBlue.setFill()
NSBezierPath(roundedRect: NSRect(x: 30, y: 30, width: 452, height: 452), xRadius: 100, yRadius: 100).fill()
if let symbol = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)?
    .withSymbolConfiguration(.init(pointSize: 240, weight: .medium))?
    .withSymbolConfiguration(.init(paletteColors: [.white])) {
    symbol.draw(in: NSRect(x: 115, y: 125, width: 285, height: 240))
}
NSGraphicsContext.restoreGraphicsState()
let png = bitmap.representation(using: .png, properties: [:])!
// icns 的 ic09 块是 512 × 512 PNG，不需要外部图像工具。
var content = Data("icns".utf8)
var total = UInt32(png.count + 16).bigEndian
withUnsafeBytes(of: &total) { content.append(contentsOf: $0) }
content.append(Data("ic09".utf8))
var block = UInt32(png.count + 8).bigEndian
withUnsafeBytes(of: &block) { content.append(contentsOf: $0) }
content.append(png)
try content.write(to: output)
