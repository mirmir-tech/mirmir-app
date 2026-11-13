// Draws the disk image window's background at one scale.
//
//   swift scripts/dmg/background.swift <out.png> <scale> <version>
//
// The layout matches scripts/release.sh: a 660×400 pt window with the app
// icon centred at (170, 190) and Applications at (490, 190), 128 pt icons.
// Finder draws the icon labels itself, so the background leaves room below
// each icon and draws no names.
import AppKit
import CoreText

let arguments = CommandLine.arguments
guard arguments.count == 4, let scale = Double(arguments[2]) else {
    FileHandle.standardError.write(Data("usage: background.swift <out.png> <scale> <version>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1])
let version = arguments[3]

let size = CGSize(width: 660, height: 400)
let appCenter = CGPoint(x: 170, y: 190)
let applicationsCenter = CGPoint(x: 490, y: 190)

// Palette tokens (web/public/assets/theme.css), light variant.
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let canvas = color(0xF7F8FA)
let surface = color(0xFFFFFF)
let border = color(0xDDE3EB)
let ink = color(0x20242B)
let muted = color(0x596473)
let signal = color(0x2563EB)

let pixels = CGSize(width: size.width * scale, height: size.height * scale)
let context = CGContext(
    data: nil, width: Int(pixels.width), height: Int(pixels.height), bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.scaleBy(x: scale, y: scale)
// Top-left origin, like Finder's icon positions.
context.translateBy(x: 0, y: size.height)
context.scaleBy(x: 1, y: -1)

context.setFillColor(canvas)
context.fill(CGRect(origin: .zero, size: size))

// A soft surface card behind each icon and its label.
for center in [appCenter, applicationsCenter] {
    let card = CGRect(x: center.x - 92, y: center.y - 92, width: 184, height: 200)
    let path = CGPath(roundedRect: card, cornerWidth: 18, cornerHeight: 18, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 16, color: color(0x141C28, 0.08))
    context.addPath(path)
    context.setFillColor(surface)
    context.fillPath()
    context.restoreGState()
    context.addPath(path)
    context.setStrokeColor(border)
    context.setLineWidth(1)
    context.strokePath()
}

// The arrow from the app to Applications.
let arrowStart = CGPoint(x: appCenter.x + 104, y: appCenter.y)
let arrowEnd = CGPoint(x: applicationsCenter.x - 104, y: applicationsCenter.y)
context.setStrokeColor(signal)
context.setLineWidth(3)
context.setLineCap(.round)
context.setLineJoin(.round)
context.setLineDash(phase: 0, lengths: [2, 9])
context.move(to: arrowStart)
context.addLine(to: CGPoint(x: arrowEnd.x - 8, y: arrowEnd.y))
context.strokePath()
context.setLineDash(phase: 0, lengths: [])
context.move(to: CGPoint(x: arrowEnd.x - 12, y: arrowEnd.y - 10))
context.addLine(to: arrowEnd)
context.addLine(to: CGPoint(x: arrowEnd.x - 12, y: arrowEnd.y + 10))
context.strokePath()

// Text, drawn with Core Text in the flipped context.
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: CGColor, centerX: CGFloat, baseline: CGFloat, mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color)!, .kern: mono ? 1.2 : -0.1,
    ]))
    let width = CTLineGetTypographicBounds(line, nil, nil, nil)
    context.saveGState()
    context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    context.textPosition = CGPoint(x: centerX - width / 2, y: baseline)
    CTLineDraw(line, context)
    context.restoreGState()
}
draw("MIRMIR FOR MAC · \(version)", size: 11, weight: .semibold, color: signal, centerX: size.width / 2, baseline: 44, mono: true)
draw("Drag Mirmir to Applications", size: 20, weight: .semibold, color: ink, centerX: size.width / 2, baseline: 74)
draw("Includes the mirmir runtime · Apple silicon · macOS 27 or later", size: 12, weight: .regular, color: muted, centerX: size.width / 2, baseline: 368)

let image = context.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
rep.size = size
try rep.representation(using: .png, properties: [:])!.write(to: output)
