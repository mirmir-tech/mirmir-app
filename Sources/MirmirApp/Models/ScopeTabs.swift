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

    func makeNSView(context: Context) -> BadgeSegmentedControl {
        let control = BadgeSegmentedControl()
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
            // Every segment gets a little more room than its title needs, and
            // Downloading the pill's on top: its centred title then sits only
            // a few points further from its edges than the others'.
            let room = item == .downloading ? BadgeSegmentedControl.reserved : 0
            control.setWidth((text + 32 + room).rounded(.up), forSegment: index)
        }
        control.badgeSegment = Self.scopes.firstIndex(of: .downloading)
        return control
    }

    func updateNSView(_ control: BadgeSegmentedControl, context: Context) {
        context.coordinator.scope = $scope
        if let index = Self.scopes.firstIndex(of: scope), control.selectedSegment != index {
            control.selectedSegment = index
        }
        control.badge = downloads > 0 ? (downloads > 9 ? "9+" : "\(downloads)") : nil
        if let index = control.badgeSegment {
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

/// A segmented control with a count pill at the trailing edge of one
/// segment. The pill is a subview: the toolbar draws the control with a cell
/// of its own, and a custom cell class draws it dimmed, without selection.
final class BadgeSegmentedControl: NSSegmentedControl {
    /// Extra width for the pill, sized for "9+" beside the centred title.
    static let reserved: CGFloat = 22
    var badgeSegment: Int?
    var badge: String? {
        didSet {
            guard badge != oldValue else { return }
            pill.text = badge
            pill.isHidden = badge == nil
            needsLayout = true
        }
    }

    private let pill = BadgePill()

    override init(frame: NSRect) {
        super.init(frame: frame)
        pill.isHidden = true
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        guard let segment = badgeSegment, segment < segmentCount else { return }
        let widths = (0..<segmentCount).map { width(forSegment: $0) }
        // Segments are centred in the bounds; the pill ends 6 pt inside
        // the trailing edge of its segment.
        let inset = (bounds.width - widths.reduce(0, +)) / 2
        let trailing = inset + widths[0...segment].reduce(0, +) - 5
        let size = pill.intrinsicContentSize
        pill.frame = NSRect(x: trailing - size.width, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// Clicks reach the segment under the pill.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === pill ? self : hit
    }
}

/// The count: white on the accent colour, in a capsule.
final class BadgePill: NSView {
    var text: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    private static let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold),
        .foregroundColor: NSColor.white,
    ]

    override var intrinsicContentSize: NSSize {
        let width = ((text ?? "") as NSString).size(withAttributes: Self.attributes).width
        return NSSize(width: max(width + 8, 14), height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let text else { return }
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
        let size = (text as NSString).size(withAttributes: Self.attributes)
        (text as NSString).draw(
            at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: Self.attributes
        )
    }
}
