import MirmirKit
import SwiftUI

/// The one server every screen shows, at the top of the sidebar: who it is,
/// whether it serves, and a menu to switch to another or manage the list.
struct ServerSwitcher: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let current = model.currentInstance
        Menu {
            Section("Show Server") {
                ForEach(model.instances) { record in
                    Button { model.select(instance: record.id) } label: {
                        if record.id == model.currentInstanceID {
                            Label(record.name, systemImage: "checkmark")
                        } else {
                            Text(record.name)
                        }
                        Text(menuDetail(record))
                    }
                }
            }
            Divider()
            Button("Manage Servers…") { model.section = .instances }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SERVER").sectionLabel()
                    HStack(spacing: 6) {
                        StatusDot(color: phaseColor)
                        Text(current.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                    Text(location(current)).font(.mono(11)).foregroundStyle(Palette.muted).lineLimit(1).truncationMode(.middle)
                    Text(serving).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.muted).padding(.top, 18)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border, lineWidth: 0.5))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel("Server: \(current.name)")
        .accessibilityHint("Switches the server every screen shows")
    }

    private func location(_ record: InstanceRecord) -> String {
        if case .remote(let endpoint) = record.target { return endpoint.address }
        return record.target.kind.label.lowercased()
    }

    private func menuDetail(_ record: InstanceRecord) -> String {
        "\(location(record)) · \(model.summary(for: record).status.label)"
    }

    /// Status, server version and device of the current server.
    private var serving: String {
        let state = switch model.phase {
        case .connected: "Serving"
        case .connecting: "Connecting…"
        case .startingServer: "Starting mirmir…"
        case .offline: "Offline"
        }
        var parts = [state]
        if let connection = model.connection { parts.append("mirmir \(connection.health.serverVersion)") }
        if let device = model.telemetry?.deviceName, !device.isEmpty { parts.append(device) }
        return parts.joined(separator: " · ")
    }

    private var phaseColor: Color {
        switch model.phase {
        case .connected: Palette.success
        case .connecting, .startingServer: Palette.warning
        case .offline: Palette.muted
        }
    }
}

#if DEBUG
#Preview("Server switcher", traits: .sizeThatFitsLayout) {
    ServerSwitcher().frame(width: 210).padding().previewModel()
}
#endif
