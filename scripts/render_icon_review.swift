import AppKit
import Foundation

// QA contact sheet only: downscale the AI artwork and compare its grayscale silhouette.
// This does not redraw, recolor, mask, or overwrite any delivered icon.
struct Manifest: Decodable {
    struct Icon: Decodable {
        let name: String
        let file: String
        let title: String?
        let palette: [[String]]?
    }
    let title: String?
    let gridTitle: String?
    let icons: [Icon]
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else { fatalError("Usage: render_icon_review.swift ICON_DIRECTORY") }
let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: directory.appendingPathComponent("prompts.json")))
let width = 840
let height = 160 + 144 * manifest.icons.count
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
let canvas = NSGraphicsContext.current!.cgContext
canvas.setFillColor(CGColor(gray: 0.97, alpha: 1))
canvas.fill(CGRect(x: 0, y: 0, width: width, height: height))

func label(_ string: String, x: Double, top: Double, size: Double = 15, bold: Bool = false) {
    (string as NSString).draw(at: NSPoint(x: x, y: Double(height) - top - size - 3), withAttributes: [
        .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
        .foregroundColor: NSColor.black
    ])
}

func thumbnail(_ source: CGImage, size: Int, gray: Bool) -> CGImage {
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: gray ? CGColorSpaceCreateDeviceGray() : CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: gray ? CGImageAlphaInfo.none.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue)!
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
    return context.makeImage()!
}

label(manifest.title ?? "\(manifest.icons.count) icon concepts.", x: 24, top: 22, size: 27, bold: true)
label("AI-generated artwork • Square exports • No text or rounded masks in the icons", x: 24, top: 62, size: 14)
label("Name", x: 24, top: 102, bold: true)
for (title, x) in [("128 px", 205.0), ("60 px", 390.0), ("40 px", 490.0), ("Gray 60 px", 590.0), ("Gray 40 px", 715.0)] {
    label(title, x: x, top: 102, bold: true)
}

for (index, icon) in manifest.icons.enumerated() {
    let url = directory.appendingPathComponent(icon.file)
    guard let source = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Cannot load \(url.path)")
    }
    precondition(source.width == 1024 && source.height == 1024, "Expected a 1024×1024 export: \(icon.name)")
    let top = Double(132 + 144 * index)
    label(icon.name, x: 24, top: top + 47, size: 19, bold: true)
    if let title = icon.title { label(title, x: 24, top: top + 73, size: 13) }
    for (x, size, gray) in [(205.0, 128, false), (390.0, 60, false), (490.0, 40, false),
                            (605.0, 60, true), (730.0, 40, true)] {
        let image = thumbnail(source, size: size, gray: gray)
        canvas.interpolationQuality = .none
        canvas.draw(image, in: CGRect(x: x, y: Double(height) - top - 64 - Double(size) / 2,
                                      width: Double(size), height: Double(size)))
    }
    print("Verified \(icon.name): 1024×1024; rendered 40/60 px color and grayscale previews")
}

NSGraphicsContext.restoreGraphicsState()
let output = directory.appendingPathComponent("review-sheet.png")
try bitmap.representation(using: .png, properties: [:])!.write(to: output, options: .atomic)
print(output.path)

// A larger comparison grid keeps the detailed concepts and their palette swatches together.
// Swatches and labels are outside the artwork and never added to the exported icons.
if let gridTitle = manifest.gridTitle {
    let gridWidth = 960
    let gridHeight = 120 + 374 * ((manifest.icons.count + 2) / 3)
    let grid = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: gridWidth, pixelsHigh: gridHeight,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: grid)!
    let context = NSGraphicsContext.current!.cgContext
    context.setFillColor(CGColor(gray: 0.97, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight))
    func gridLabel(_ text: String, x: Double, top: Double, size: Double, bold: Bool = false) {
        (text as NSString).draw(at: NSPoint(x: x, y: Double(gridHeight) - top - size - 3), withAttributes: [
            .font: bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size),
            .foregroundColor: NSColor.black
        ])
    }
    gridLabel(gridTitle, x: 40, top: 24, size: 30, bold: true)
    gridLabel("AI-generated • Four-color palettes with tonal shading • Icons shown at 256 px", x: 40, top: 68, size: 15)
    for (index, icon) in manifest.icons.enumerated() {
        let x = Double(40 + 300 * (index % 3))
        let top = Double(112 + 374 * (index / 3))
        gridLabel(icon.name, x: x, top: top, size: 20, bold: true)
        let source = NSImage(contentsOf: directory.appendingPathComponent(icon.file))!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        context.draw(thumbnail(source, size: 256, gray: false),
            in: CGRect(x: x, y: Double(gridHeight) - top - 292, width: 256, height: 256))
        gridLabel(icon.title ?? "", x: x, top: top + 300, size: 17)
        for (offset, color) in (icon.palette ?? []).enumerated() {
            guard color.count == 2, let rgb = UInt32(color[1].dropFirst(), radix: 16) else { continue }
            context.setFillColor(CGColor(red: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1))
            context.fill(CGRect(x: x + Double(offset * 26), y: Double(gridHeight) - top - 346, width: 20, height: 16))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    let gridURL = directory.appendingPathComponent("exploration-sheet.png")
    try grid.representation(using: .png, properties: [:])!.write(to: gridURL, options: .atomic)
    print(gridURL.path)
}
