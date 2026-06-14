import AppKit

// Renders the Murmur app icon: amber waveform bars on a dark squircle.
// Usage: swift render_icon.swift <output.png>

let size = 1024.0
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.clear(CGRect(x: 0, y: 0, width: size, height: size))

// Rounded-square (macOS squircle approximation), inset so the system can add shadow.
let inset = 96.0
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let radius = (size - 2 * inset) * 0.2237
ctx.saveGState()
ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()

// Dark vertical gradient background.
let bg = CGGradient(
    colorsSpace: CGColorSpaceCreateDeviceRGB(),
    colors: [CGColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1),
             CGColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 1)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// Amber waveform bars, centered, symmetric short→tall→short.
let amber = CGColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)
ctx.setFillColor(amber)
let cx = size / 2, cy = size / 2
let heights: [Double] = [0.30, 0.52, 0.80, 1.0, 0.80, 0.52, 0.30]
let barW = 60.0
let gap = 44.0
let totalW = Double(heights.count) * barW + Double(heights.count - 1) * gap
var x = cx - totalW / 2
let maxH = 540.0
for h in heights {
    let bh = maxH * h
    let bar = CGRect(x: x, y: cy - bh / 2, width: barW, height: bh)
    ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
    ctx.fillPath()
    x += barW + gap
}
ctx.restoreGState()

NSGraphicsContext.restoreGraphicsState()
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/murmur_icon_1024.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
