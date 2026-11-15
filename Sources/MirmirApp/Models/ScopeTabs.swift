import AppKit
import MirmirKit
import SwiftUI

/// The Models screen's scopes: a native segmented control whose Downloading
/// segment has a fixed width with room for a count pill (1 to 9, then 9+),
/// so a download starting or ending never resizes the control. A SwiftUI
/// segmented Picker can neither size one segment nor show a pill in it.
struct ScopeTabs: NSViewRepresentable {
    @Binding var scope: ModelScope
    let downloads: Int

    static let scopes = ModelScope.allCases

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl()
        let cell = BadgeSegmentCell()
        control.cell = cell
        control.segmentCount = Self.scopes.count
        control.trackingMode = .selectOne
        control.segmentStyle = .automatic
        control.target = context.coordinator
        control.action = #selector(Coordinator.changed(_:))
        control.toolTip = "Filter this server's models, or search Hugging Face to download one"
        let font = control.font ?? .systemFont(ofSize: NSFont.systemFontSize)
        for (index, item) in Self.scopes.enumerated() {
            control.setLabel(item.title, forSegment: index)
            let text = (item.title as NSString).size(withAttributes: [.font: font]).width
            // The title stays centred: the pill's room is kept on both sides.
            let room = item == .downloading ? 2 * BadgeSegmentCell.reserved : 0
            control.setWidth((text + 24 + room).rounded(.up), forSegment: index)
        }
        cell.badgeSegment = Self.scopes.firstIndex(of: .downloading)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.scope = $scope
        if let index = Self.scopes.firstIndex(of: scope), control.selectedSegment != index {
            control.selectedSegment = index
        }
        guard let cell = control.cell as? BadgeSegmentCell else { return }
        let badge = downloads > 0 ? (downloads > 9 ? "9+" : "\(downloads)") : nil
        if cell.badge != badge {
            cell.badge = badge
            control.needsDisplay = true
        }
        if let index = cell.badgeSegment {
            control.setToolTip(downloads > 0 ? "\(downloads) downloading" : nil, forSegment: index)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(scope: $scope) }

    @MainActor
    final class Coordinator: NSObject {
        var scope: Binding<ModelScope>

        init(scope: Binding<ModelScope>) { self.scope = scope }

        @objc func changed(_ control: NSSegmentedControl) {
            guard ScopeTabs.scopes.indices.contains(control.selectedSegment) else { return }
            scope.wrappedValue = ScopeTabs.scopes[control.selectedSegment]
        }
    }
}

/// Draws a count pill at the trailing edge of one segment.
final class BadgeSegmentCell: NSSegmentedCell {
    /// Width kept free for the pill, sized for "9+".
    static let reserved: CGFloat = 28
    var badgeSegment: Int?
    var badge: String?

    override func drawSegment(_ segment: Int, inFrame frame: NSRect, with controlView: NSView) {
        super.drawSegment(segment, inFrame: frame, with: controlView)
        guard segment == badgeSegment, let badge else { return }
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (badge as NSString).size(withAttributes: attributes)
        let width = max(size.width + 10, 18)
        let pill = NSRect(x: frame.maxX - width - 6, y: frame.midY - 8, width: width, height: 16)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        (badge as NSString).draw(
            at: NSPoint(x: pill.midX - size.width / 2, y: pill.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
