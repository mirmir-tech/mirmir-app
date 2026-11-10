import AppKit
import SwiftUI

/// The MiRMiR mark from `web/public/assets/brand/mark.svg`: two crossed paths
/// forming an M, drawn in a 64-unit box.
struct MarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 64
        let origin = CGPoint(x: rect.midX - 32 * scale, y: rect.midY - 32 * scale)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + x * scale, y: origin.y + y * scale)
        }
        var path = Path()
        path.move(to: point(8, 52))
        path.addLine(to: point(8, 12))
        path.addLine(to: point(42, 46))
        path.move(to: point(52, 52))
        path.addLine(to: point(52, 12))
        path.addLine(to: point(18, 46))
        return path
    }
}

struct Mark: View {
    var lineWidth: CGFloat = 2

    var body: some View {
        MarkShape().stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
    }
}

/// The mark on an accent tile, as in the menu bar panel header.
struct MarkTile: View {
    var size: CGFloat = 30

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27)
            .fill(Palette.signal)
            .frame(width: size, height: size)
            .overlay(Mark(lineWidth: size * 0.075).foregroundStyle(Palette.onSignal).padding(size * 0.2))
    }
}

enum MarkImage {
    /// A template image for the menu bar, so macOS tints it for the bar.
    @MainActor
    static let menuBar: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            let path = NSBezierPath()
            let scale = rect.width / 64
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: y * scale) }
            path.move(to: point(8, 52)); path.line(to: point(8, 12)); path.line(to: point(42, 46))
            path.move(to: point(52, 52)); path.line(to: point(52, 12)); path.line(to: point(18, 46))
            path.lineWidth = 7 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
