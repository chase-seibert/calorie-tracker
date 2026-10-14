import AppKit
import Foundation

let output = CommandLine.arguments.dropFirst().first.map(URL.init(fileURLWithPath:))
    ?? URL(fileURLWithPath: "docs/chase-food-bagel-concept.pdf")
let page = NSRect(x: 0, y: 0, width: 900, height: 660)

final class BagelConceptPage: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let ink = NSColor(calibratedRed: 0.10, green: 0.17, blue: 0.15, alpha: 1)
        let muted = NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.45, alpha: 1)
        let coral = NSColor(calibratedRed: 0.82, green: 0.31, blue: 0.16, alpha: 1)
        let pale = NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1)
        let card = NSColor.white
        let green = NSColor(calibratedRed: 0.19, green: 0.47, blue: 0.34, alpha: 1)
        let line = NSColor(calibratedRed: 0.87, green: 0.89, blue: 0.86, alpha: 1)

        pale.setFill(); bounds.fill()
        text("CHASE FOOD  ·  BAGEL CUSTOMIZATION CONCEPT", x: 38, y: 24, w: 800, h: 20, size: 10, color: coral, bold: true)
        text("Bagel", x: 38, y: 47, w: 400, h: 42, size: 32, color: ink, bold: true)
        text("One canonical food with a choice of type and optional spreads.", x: 40, y: 87, w: 600, h: 24, size: 14, color: muted)

        rounded(x: 38, y: 124, w: 328, h: 492, radius: 27, fill: ink)
        rounded(x: 46, y: 132, w: 312, h: 476, radius: 23, fill: card)
        text("9:41", x: 65, y: 147, w: 60, h: 18, size: 12, color: ink, bold: true)
        text("‹  Back to results", x: 64, y: 177, w: 160, h: 20, size: 12, color: coral, bold: true)
        text("Customize food", x: 64, y: 218, w: 220, h: 22, size: 16, color: muted, bold: true)
        text("Bagel", x: 64, y: 243, w: 240, h: 37, size: 28, color: ink, bold: true)
        text("Chase Food", x: 65, y: 280, w: 160, h: 20, size: 12, color: green, bold: true)

        text("PORTION", x: 64, y: 318, w: 100, h: 15, size: 10, color: muted, bold: true)
        chip("Small · 70 g", x: 64, y: 341, w: 87, selected: false, ink: ink, muted: muted, coral: coral, line: line)
        chip("Medium · 105 g", x: 157, y: 341, w: 105, selected: true, ink: ink, muted: muted, coral: coral, line: line)
        chip("Large · 140 g", x: 268, y: 341, w: 75, selected: false, ink: ink, muted: muted, coral: coral, line: line)

        text("BAGEL TYPE · CHOOSE ONE", x: 64, y: 383, w: 230, h: 15, size: 10, color: muted, bold: true)
        rounded(x: 63, y: 403, w: 278, h: 37, radius: 9, fill: NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.95, alpha: 1), stroke: line)
        text("Plain bagel (default)", x: 77, y: 413, w: 235, h: 19, size: 12, color: ink, bold: true)
        text("⌄", x: 317, y: 412, w: 14, h: 20, size: 14, color: muted)

        text("SPREADS · OPTIONAL", x: 64, y: 451, w: 220, h: 15, size: 10, color: muted, bold: true)
        rounded(x: 63, y: 470, w: 278, h: 39, radius: 9, fill: NSColor(calibratedRed: 0.99, green: 0.91, blue: 0.86, alpha: 1), stroke: coral)
        text("●", x: 76, y: 480, w: 14, h: 18, size: 11, color: coral, bold: true)
        text("Cream cheese", x: 96, y: 477, w: 142, h: 17, size: 12, color: ink, bold: true)
        text("30 g · 105 kcal", x: 96, y: 492, w: 160, h: 14, size: 10, color: muted)
        text("Butter  ·  Peanut butter  ·  Jam", x: 66, y: 515, w: 275, h: 18, size: 10, color: muted)

        rounded(x: 63, y: 540, w: 278, h: 51, radius: 12, fill: NSColor(calibratedRed: 0.89, green: 0.95, blue: 0.90, alpha: 1))
        text("382 kcal", x: 77, y: 548, w: 140, h: 25, size: 20, color: green, bold: true)
        text("Carbs 56.7 g   ·   Fat 11.7 g   ·   Protein 13.0 g", x: 77, y: 574, w: 255, h: 13, size: 9, color: muted)
        rounded(x: 63, y: 594, w: 278, h: 1, radius: 0, fill: line)
        text("Selected components are saved with the Bagel entry.", x: 64, y: 596, w: 278, h: 12, size: 8, color: muted)

        text("BAGEL TYPE OPTIONS", x: 402, y: 130, w: 400, h: 19, size: 12, color: coral, bold: true)
        text("One choice · values shown for a 105 g portion", x: 402, y: 153, w: 450, h: 18, size: 11, color: muted)
        let types: [(String, String, String)] = [
            ("Plain", "277 kcal", "High · USDA FDC"),
            ("Whole wheat", "263 kcal", "Medium · miniature record scaled"),
            ("Multigrain", "253 kcal", "Medium · serving scaled"),
            ("Cinnamon raisin", "288 kcal", "Medium · miniature record scaled"),
            ("Egg", "292 kcal", "Medium · ounce profile scaled"),
            ("Pumpernickel", "263 kcal", "Medium · miniature record scaled"),
            ("Sesame", "277 kcal", "Low · plain bagel analog"),
            ("Everything", "277 kcal", "Medium · USDA mixed-topping analog"),
        ]
        var y: CGFloat = 180
        for (name, kcal, evidence) in types {
            rounded(x: 402, y: y, w: 458, h: 34, radius: 8, fill: card, stroke: line)
            text(name, x: 414, y: y + 6, w: 172, h: 18, size: 11, color: ink, bold: true)
            text(kcal, x: 590, y: y + 6, w: 72, h: 18, size: 10, color: green, bold: true)
            text(evidence, x: 664, y: y + 6, w: 186, h: 18, size: 9, color: muted)
            y += 39
        }

        rounded(x: 402, y: 504, w: 458, h: 61, radius: 11, fill: NSColor(calibratedRed: 0.99, green: 0.91, blue: 0.86, alpha: 1), stroke: NSColor(calibratedRed: 0.94, green: 0.77, blue: 0.68, alpha: 1))
        text("OPTIONAL SPREAD", x: 416, y: 514, w: 180, h: 14, size: 9, color: coral, bold: true)
        text("Cream cheese · 30 g", x: 416, y: 532, w: 220, h: 20, size: 12, color: ink, bold: true)
        text("+105 kcal · +1.7 C · +10.3 F · +1.8 P", x: 630, y: 533, w: 220, h: 18, size: 10, color: muted)

        text("SEARCH & HISTORY", x: 402, y: 579, w: 200, h: 14, size: 9, color: coral, bold: true)
        text("“Bagel with cream cheese” and bagel-type aliases resolve to Bagel. The former combined ID stays history-only.", x: 402, y: 596, w: 458, h: 29, size: 9, color: ink)
        text("Sources: USDA FoodData Central records 2707684, 2707733, 171852, 172664, 174901, 2707762; cream cheese 173418. Sesame/everything are flagged analogs. Portion sizes Small/Large are estimates; Medium is USDA 105 g.", x: 38, y: 632, w: 822, h: 20, size: 7.5, color: muted)
    }

    private func rounded(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
        let rect = NSRect(x: x, y: bounds.height - y - h, width: w, height: h)
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill(); path.fill()
        if let stroke { stroke.setStroke(); path.lineWidth = 1; path.stroke() }
    }

    private func text(_ value: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false) {
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        (value as NSString).draw(in: NSRect(x: x, y: bounds.height - y - h, width: w, height: h), withAttributes: [.font: font, .foregroundColor: color])
    }

    private func chip(_ title: String, x: CGFloat, y: CGFloat, w: CGFloat, selected: Bool, ink: NSColor, muted: NSColor, coral: NSColor, line: NSColor) {
        let fill = selected ? NSColor(calibratedRed: 0.99, green: 0.89, blue: 0.83, alpha: 1) : NSColor.white
        rounded(x: x, y: y, w: w, h: 30, radius: 15, fill: fill, stroke: selected ? coral : line)
        text(title, x: x + 5, y: y + 7, w: w - 10, h: 16, size: 8.5, color: selected ? coral : ink, bold: selected)
    }
}

let view = BagelConceptPage(frame: page)
view.wantsLayer = true
let data = view.dataWithPDF(inside: page)
try data.write(to: output, options: .atomic)
print(output.path)
