import AppKit

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let side = 1024

guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: side,
    pixelsHigh: side,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    FileHandle.standardError.write(Data("Não foi possível criar o bitmap.\n".utf8))
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context

let canvas = NSRect(x: 64, y: 64, width: 896, height: 896)
let background = NSBezierPath(roundedRect: canvas, xRadius: 200, yRadius: 200)
background.addClip()

NSGradient(colors: [
    NSColor(srgbRed: 0.17, green: 0.23, blue: 0.35, alpha: 1),
    NSColor(srgbRed: 0.04, green: 0.06, blue: 0.10, alpha: 1)
])?.draw(in: background, angle: -90)

NSGradient(colors: [
    NSColor(srgbRed: 1.0, green: 0.35, blue: 0.22, alpha: 0.22),
    NSColor(srgbRed: 1.0, green: 0.35, blue: 0.22, alpha: 0.0)
])?.draw(
    in: NSBezierPath(ovalIn: NSRect(x: 210, y: 110, width: 604, height: 604)),
    relativeCenterPosition: NSPoint(x: 0, y: -0.2)
)

NSColor.white.withAlphaComponent(0.07).setStroke()
background.lineWidth = 5
background.stroke()

let bodyColor = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1)
let bulbRect = NSRect(x: 512 - 142, y: 286 - 142, width: 284, height: 284)
let stemRect = NSRect(x: 512 - 55, y: 330, width: 110, height: 435)

bodyColor.setFill()
NSBezierPath(ovalIn: bulbRect).fill()
NSBezierPath(roundedRect: stemRect, xRadius: 55, yRadius: 55).fill()

let innerBulb = NSBezierPath(ovalIn: NSRect(x: 512 - 96, y: 286 - 96, width: 192, height: 192))
let innerStem = NSBezierPath(roundedRect: NSRect(x: 512 - 21, y: 360, width: 42, height: 330), xRadius: 21, yRadius: 21)
innerBulb.append(innerStem)

NSGradient(colors: [
    NSColor(srgbRed: 1.0, green: 0.42, blue: 0.30, alpha: 1),
    NSColor(srgbRed: 0.84, green: 0.10, blue: 0.11, alpha: 1)
])?.draw(in: innerBulb, angle: -90)

NSColor(srgbRed: 1.0, green: 0.86, blue: 0.82, alpha: 0.55).setFill()
NSBezierPath(ovalIn: NSRect(x: 448, y: 330, width: 46, height: 62)).fill()

NSColor.white.withAlphaComponent(0.22).setFill()
NSBezierPath(roundedRect: NSRect(x: 476, y: 430, width: 14, height: 250), xRadius: 7, yRadius: 7).fill()

let ticks = NSBezierPath()
for y in stride(from: 690, through: 420, by: -90) {
    ticks.move(to: NSPoint(x: 596, y: y))
    ticks.line(to: NSPoint(x: 628, y: y))
}
NSColor.white.withAlphaComponent(0.40).setStroke()
ticks.lineWidth = 12
ticks.lineCapStyle = .round
ticks.stroke()

NSGraphicsContext.restoreGraphicsState()

guard let data = bitmap.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("Não foi possível gerar o PNG.\n".utf8))
    exit(1)
}

do {
    try data.write(to: URL(fileURLWithPath: outputPath))
} catch {
    FileHandle.standardError.write(Data("Erro ao escrever \(outputPath): \(error)\n".utf8))
    exit(1)
}
