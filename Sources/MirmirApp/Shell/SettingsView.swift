import MirmirKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(ServerBinary.overrideKey) private var binaryPath = ""

    var body: some View {
        Form {
            Section("Local server") {
                TextField("mirmir binary", text: $binaryPath, prompt: Text(ServerBinary.resolve(override: nil)?.path ?? "not found"))
                    .font(.mono(12))
                LabeledContent("Personal socket", value: SocketPaths().personalSocket).font(.mono(11))
                LabeledContent("Status", value: ownership)
            }
            Section("About") {
                LabeledContent("Client protocol", value: clientProtocolVersion)
                if let health = model.connection?.health {
                    LabeledContent("Server", value: "mirmir \(health.serverVersion) · protocol \(health.protocolVersion)")
                }
            }
        }
        .formStyle(.grouped)
        .paletteBackground(Palette.canvas)
        .frame(width: 520)
        .padding(.vertical, 8)
    }

    private var ownership: String {
        switch model.supervisor.ownership {
        case .none: model.connection == nil ? "Not running" : "Attached to a server started outside the app"
        case .running(let pid, _): "Started by this app (pid \(pid))"
        case .exited(let status): "Exited with status \(status)"
        case .unavailable(let reason): reason
        }
    }
}

#if DEBUG
#Preview("Settings") { SettingsView().previewModel() }
#endif
