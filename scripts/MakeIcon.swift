import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let dimensions: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]
for (name, size) in dimensions {
    let side = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: side, height: side)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let background = NSRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9)
    NSColor(srgbRed: 0.23, green: 0.38, blue: 0.29, alpha: 1).setFill()
    NSBezierPath(roundedRect: background, xRadius: side * 0.2, yRadius: side * 0.2).fill()
    let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.61, weight: .medium)
        .applying(.init(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "figure.stand", accessibilityDescription: nil)?
        .withSymbolConfiguration(configuration) {
        let scale = min(side * 0.56 / symbol.size.width, side * 0.65 / symbol.size.height)
        let width = symbol.size.width * scale, height = symbol.size.height * scale
        let rect = NSRect(x: (side - width) / 2, y: (side - height) / 2, width: width, height: height)
        symbol.isTemplate = false
        symbol.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

// Package the PNG representations directly, without an external image converter.
func encodedSize(_ count: Int) -> Data {
    var size = UInt32(count).bigEndian
    return withUnsafeBytes(of: &size) { Data($0) }
}
let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"), ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"), ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]
var chunks = Data()
for (type, name) in entries {
    let image = try Data(contentsOf: output.appendingPathComponent(name))
    chunks.append(Data(type.utf8))
    chunks.append(encodedSize(image.count + 8))
    chunks.append(image)
}
var icon = Data("icns".utf8)
icon.append(encodedSize(chunks.count + 8))
icon.append(chunks)
let destination = URL(fileURLWithPath: CommandLine.arguments[2])
try icon.write(to: destination)
guard let decoded = NSImage(contentsOf: destination), decoded.isValid else {
    fatalError("Generated app icon could not be read by AppKit")
}
