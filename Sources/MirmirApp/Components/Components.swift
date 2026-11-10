import MirmirKit
import SwiftUI

/// A rounded status pill: soft tinted background, strong foreground.
struct Pill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Palette.soft(color), in: Capsule())
    }
}

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}

/// `tools` / `think` / `vision` chips with the artboard colors.
struct FeatureChips: View {
    let features: ModelFeatures
    var long = false

    var body: some View {
        HStack(spacing: 4) {
            if features.contains(.tools) { chip(long ? "Tools" : "tools", "wrench.adjustable", Palette.signal) }
            if features.contains(.thinking) { chip(long ? "Thinking" : "think", "lightbulb", Palette.brass) }
            if features.contains(.vision) { chip(long ? "Vision" : "vision", "eye", Palette.success) }
        }
    }

    private func chip(_ label: String, _ symbol: String, _ color: Color) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Palette.soft(color), in: RoundedRectangle(cornerRadius: 5))
    }
}

/// A number with a muted unit, e.g. `108.6 tok/s`.
struct Metric: View {
    let value: String
    let unit: String
    var size: CGFloat = 13

    var body: some View {
        (Text(value).font(.mono(size, weight: .semibold))
            + Text(" \(unit)").font(.mono(size * 0.55 < 10 ? 11 : size * 0.5)).foregroundStyle(Palette.muted))
            .monospacedDigit()
    }
}

/// Stacked horizontal bar for memory, as in the menu bar panel.
struct StackedBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let fraction: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    segment.color.frame(width: proxy.size.width * min(max(segment.fraction, 0), 1))
                }
                Spacer(minLength: 0)
            }
            .background(Palette.raised)
            .clipShape(Capsule())
        }
        .frame(height: height)
    }
}

/// A full-height empty state for screens without data.
struct EmptyState: View {
    let title: String
    let message: String
    var symbol = "tray"

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message))
    }
}

extension InstanceStatus {
    var label: String {
        switch self {
        case .checking: "Checking"
        case .online: "Online"
        case .updateNeeded: "Update needed"
        case .offline: "Offline"
        }
    }

    var color: Color {
        switch self {
        case .checking: Palette.muted
        case .online: Palette.success
        case .updateNeeded: Palette.warning
        case .offline: Palette.muted
        }
    }
}

extension LocalModelState {
    var color: Color {
        switch self {
        case .loaded: Palette.signal
        case .loading: Palette.brass
        case .available: Palette.success
        case .error, .missing: Palette.danger
        case .paused, .unrecognized: Palette.muted
        }
    }
}
