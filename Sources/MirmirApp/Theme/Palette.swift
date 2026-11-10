import AppKit
import SwiftUI

/// The website palette (`web/public/assets/theme.css`) as light/dark dynamic
/// colors. Controls stay native; these tint surfaces, series and states.
enum Palette {
    static let canvas = dynamic(0xF7F8FA, 0x11151C)
    static let surface = dynamic(0xFFFFFF, 0x181E27)
    /// Window chrome: sidebar and toolbar, from the artboards.
    static let sidebar = dynamic(0xECF0F5, 0x161C25)
    static let toolbar = dynamic(0xF7F8FA, 0x141920)
    /// Menu bar panel and the card inside it.
    static let panel = dynamic(0xF6F8FB, 0x1E252F)
    static let panelCard = dynamic(0xFFFFFF, 0x232C38)
    static let raised = dynamic(0xEEF2F7, 0x232C38)
    static let border = dynamic(0xDDE3EB, 0x344151)
    static let ink = dynamic(0x20242B, 0xEDF1F7)
    static let muted = dynamic(0x596473, 0xACB8C8)
    /// Accent, decode series, `tools`.
    static let signal = dynamic(0x2563EB, 0x85ADFF)
    static let onSignal = dynamic(0xFFFFFF, 0x0B1220)
    /// Second series (prefill), `think`.
    static let brass = dynamic(0x8A5C19, 0xD7AF6F)
    /// Online, ready, `vision`.
    static let success = dynamic(0x167344, 0x80D6A5)
    /// Update needed, prefill in progress.
    static let warning = dynamic(0x885C10, 0xE3BF78)
    /// Unload, revoke, memory limit.
    static let danger = dynamic(0xB42337, 0xFF96A5)

    static func soft(_ color: Color, _ opacity: Double = 0.13) -> Color {
        color.opacity(opacity)
    }

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

extension Font {
    /// Numbers, addresses and section labels. SF Mono with tabular digits.
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension View {
    /// A 0.5 pt bordered card on the surface color, as on the artboards.
    func card(padding: CGFloat = 14, radius: CGFloat = 10, fill: Color = Palette.surface) -> some View {
        self.padding(padding)
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    /// Replaces the system's neutral grey behind a scrolling list, table or
    /// form with a palette color, so no screen mixes the two palettes.
    func paletteBackground(_ color: Color = Palette.surface) -> some View {
        self.scrollContentBackground(.hidden).background(color)
    }

    /// Small uppercase monospace label above a value.
    func sectionLabel(_ color: Color = Palette.muted) -> some View {
        self.font(.mono(10, weight: .semibold)).tracking(0.8).foregroundStyle(color)
    }
}
