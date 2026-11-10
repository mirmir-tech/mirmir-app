import MirmirKit
import SwiftUI

/// Adds a local socket instance and tests it before saving. Remote servers
/// can be recorded, but connecting waits for mirmir's TLS listener.
struct AddInstanceSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case socket = "Unix socket", system = "System server", remote = "Remote server"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .socket
    @State private var name = ""
    @State private var path = ""
    @State private var address = ""
    @State private var test: TestResult?
    @State private var testing = false

    enum TestResult {
        case passed(ServerHealth, models: Int)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Server").font(.system(size: 15, weight: .semibold))
            Form {
                Picker("Kind", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Name", text: $name, prompt: Text(defaultName))
                switch kind {
                case .socket:
                    TextField("Socket", text: $path, prompt: Text("/path/to/mirmir.sock")).font(.mono(12))
                case .system:
                    LabeledContent("Socket", value: InstanceTarget.systemSocket).font(.mono(12))
                case .remote:
                    TextField("Address", text: $address, prompt: Text("host:7443")).font(.mono(12))
                    Text("Remote access (TLS, API keys, certificate pinning) is designed but not served by mirmir yet. The server is saved and will connect once supported.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            testView
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Test Connection", action: runTest).disabled(target == nil || kind == .remote || testing)
                Button("Add Server") {
                    guard let target else { return }
                    model.add(InstanceRecord(name: name.isEmpty ? defaultName : name, target: target))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(target == nil)
            }
        }
        .padding(20)
        .frame(width: 540)
        .background(Palette.canvas)
    }

    @ViewBuilder private var testView: some View {
        if testing {
            ProgressView("Testing…").controlSize(.small)
        } else if let test {
            switch test {
            case .passed(let health, let models):
                Label("Reachable · mirmir \(health.serverVersion) · protocol compatible · \(models) local models", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success).font(.system(size: 12))
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(Palette.danger).font(.system(size: 12))
            }
        }
    }

    private var defaultName: String {
        switch kind {
        case .socket: (path as NSString).deletingLastPathComponent.split(separator: "/").last.map(String.init) ?? "Socket"
        case .system: "System"
        case .remote: address.split(separator: ":").first.map(String.init) ?? "Remote"
        }
    }

    private var target: InstanceTarget? {
        switch kind {
        case .socket:
            return path.isEmpty ? nil : .socket(path: path)
        case .system:
            return .system
        case .remote:
            let parts = address.split(separator: ":")
            guard parts.count == 2, let port = Int(parts[1]), !parts[0].isEmpty else { return nil }
            return .remote(RemoteEndpoint(host: String(parts[0]), port: port))
        }
    }

    private func runTest() {
        guard let target, let socket = SocketPaths().socket(for: target) else { return }
        testing = true
        Task {
            do {
                let connection = try await RuntimeConnection.connect(socket: socket)
                let models = (try? await connection.localModels().count) ?? 0
                test = .passed(connection.health, models: models)
                connection.close()
            } catch {
                test = .failed(error.localizedDescription)
            }
            testing = false
        }
    }
}
