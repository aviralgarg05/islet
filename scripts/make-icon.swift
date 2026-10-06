// Draws the Casement app icon (1024 px) with AppKit. Usage: swift scripts/make-icon.swift out.png
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// macOS icon grid: 824 px body centred in 1024 with ~185 px corner radius.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)
NSGradient(colors: [NSColor(srgbRed: 0.33, green: 0.36, blue: 0.62, alpha: 1), NSColor(srgbRed: 0.72, green: 0.42, blue: 0.56, alpha: 1)])!
    .draw(in: squircle, angle: -60)

// Screen "menu bar" hint.
NSGraphicsContext.current?.saveGraphicsState()
squircle.addClip()
NSColor(white: 1, alpha: 0.16).setFill()
NSRect(x: body.minX, y: body.maxY - 150, width: body.width, height: 150).fill()
NSGraphicsContext.current?.restoreGraphicsState()

// The island: a black capsule hanging from the top edge, with a live-activity glow.
let island = NSRect(x: 232, y: 560, width: 560, height: 190)
let shadow = NSShadow()
shadow.shadowColor = NSColor(white: 0, alpha: 0.45)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -18)
NSGraphicsContext.current?.saveGraphicsState()
shadow.set()
NSColor.black.setFill()
NSBezierPath(roundedRect: island, xRadius: 95, yRadius: 95).fill()
NSGraphicsContext.current?.restoreGraphicsState()

// Leading dot (activity) and trailing level bar.
NSColor(srgbRed: 0.19, green: 0.82, blue: 0.35, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 300, y: 615, width: 80, height: 80)).fill()
NSColor(white: 1, alpha: 0.25).setFill()
NSBezierPath(roundedRect: NSRect(x: 520, y: 638, width: 200, height: 34), xRadius: 17, yRadius: 17).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 520, y: 638, width: 128, height: 34), xRadius: 17, yRadius: 17).fill()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
