import MirmirKit
import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.section) {
            Section("Mirmir") {
                ForEach(SidebarSection.allCases) { section in
                    Label(section.title, systemImage: section.symbol)
                        .badge(badge(for: section))
                        .tag(section)
                }
            }
            Section("Connected to") {
                ForEach(model.instances) { record in
                    InstanceRow(record: record, current: record.id == model.currentInstanceID)
                }
            }
        }
        .listStyle(.sidebar)
        .paletteBackground(Palette.sidebar)
        .safeAreaInset(edge: .bottom) { ServingFooter().padding(12) }
    }

    private func badge(for section: SidebarSection) -> Int {
        switch section {
        case .chat: model.chat.conversations.count
        case .models: model.models.count
        case .instances: model.instances.count
        case .sessions: model.activeOperations.count
        case .overview, .logs: 0
        }
    }
}

private struct InstanceRow: View {
    @Environment(AppModel.self) private var model
    let record: InstanceRecord
    let current: Bool

    var body: some View {
        Button { model.select(instance: record.id) } label: {
            HStack(spacing: 8) {
                StatusDot(color: model.summary(for: record).status.color)
                Text(record.name).fontWeight(current ? .semibold : .regular)
                Spacer()
                Text(record.target.kind.label.lowercased()).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 1)
    }
}

/// Bottom of the sidebar: is this instance serving, where, on what device.
struct ServingFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                StatusDot(color: color)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            if let connection = model.connection {
                Text("mirmir \(connection.health.serverVersion)").font(.mono(11)).foregroundStyle(Palette.muted)
            }
            if let device = model.telemetry?.deviceName, !device.isEmpty {
                Text(device).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sidebar)
    }

    private var title: String {
        switch model.phase {
        case .connected: "Serving"
        case .connecting: "Connecting"
        case .startingServer: "Starting"
        case .offline: "Offline"
        }
    }

    private var color: Color {
        switch model.phase {
        case .connected: Palette.success
        case .connecting, .startingServer: Palette.warning
        case .offline: Palette.muted
        }
    }
}

extension SidebarSection {
    var symbol: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .chat: "bubble.left"
        case .models: "shippingbox"
        case .instances: "server.rack"
        case .sessions: "list.bullet"
        case .logs: "doc.text"
        }
    }
}
