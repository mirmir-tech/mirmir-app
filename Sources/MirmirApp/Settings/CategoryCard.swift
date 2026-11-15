import MirmirKit
import SwiftUI

/// One part of the server's configuration: a header in the category's color
/// with what it covers, then its settings separated by hairlines.
struct CategoryCard: View {
    let category: SettingCategory
    let entries: [ConfigurationEntry]
    let busy: Bool
    let apply: (_ key: String, _ value: String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ForEach(entries) { entry in
                Rectangle().fill(Palette.border.opacity(0.7)).frame(height: 0.5)
                SettingRow(entry: entry, accent: category.color, busy: busy) { value in apply(entry.key, value) }
            }
        }
        .card(padding: 0)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: category.symbol)
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(category.color)
                .frame(width: 26, height: 26)
                .background(Palette.soft(category.color), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(category.title).sectionLabel(category.color)
                Text(category.summary).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            if entries.contains(where: \.restartRequired) {
                Label("Restart to apply", systemImage: "arrow.clockwise")
                    .font(.system(size: 10.5)).foregroundStyle(Palette.muted)
                    .help("Changes here take effect when the server restarts")
            }
            if overridden > 0 {
                Text("\(overridden) overridden").font(.mono(10, weight: .medium)).foregroundStyle(category.color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Palette.soft(category.color), in: Capsule())
            }
        }
        .padding(14)
    }

    private var overridden: Int { entries.filter(\.isOverridden).count }
}

/// A full-width notice above the cards: what happened, and what to do next.
struct Banner<Actions: View>: View {
    let symbol: String
    let color: Color
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(color)
            Text(text).font(.system(size: 12.5)).foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 8)
            actions()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Palette.soft(color, 0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(color.opacity(0.35), lineWidth: 0.5))
    }
}
