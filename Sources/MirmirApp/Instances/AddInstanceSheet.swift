import MirmirKit
import SwiftUI

/// Adds a local socket or a remote server and tests it before saving. A remote
/// server is checked step by step: its certificate fingerprint first, shown
/// for comparison before any key is sent, then the key and protocol.
struct AddInstanceSheet: View {
    enum Kind: String, CaseIterable, Identifiable {
        case socket = "Unix socket", system = "System server", remote = "Remote server"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .remote
    @State private var name = ""
    @State private var path = ""
    @State private var address = ""
    @State private var key = ""
    @State private var caIssued = false
    @State private var presented: CertificateFingerprint?
    @State private var trusted = false
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
                    remoteFields
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onChange(of: address) { resetCheck() }
            .onChange(of: caIssued) { resetCheck() }
            testView
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(test == nil ? "Test Connection" : "Test Again", action: runTest)
                    .disabled(target == nil || testing || (kind == .remote && key.isEmpty))
                Button("Add Server", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Palette.canvas)
        .onChange(of: kind) { resetCheck() }
    }

    @ViewBuilder private var remoteFields: some View {
        TextField("Address", text: $address, prompt: Text("server.local:7443")).font(.mono(12))
        SecureField("API key", text: $key, prompt: Text("mmk_…")).font(.mono(12))
        Toggle("The server uses a CA-issued certificate", isOn: $caIssued)
        if !caIssued, let presented {
            VStack(alignment: .leading, spacing: 6) {
                Text("CERTIFICATE SHA-256").sectionLabel(Palette.brass)
                Text(presented.hex).font(.mono(11)).textSelection(.enabled)
                Text("Compare it with `mirmir remote status` on the server before trusting it. A later certificate change is refused.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("Trust this certificate", isOn: $trusted)
            }
        }
        Text("Create a key on the server with `mirmir remote key create --name \(defaultName) --scope use`, or `--scope control` to manage models. The key is stored in your Keychain.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var testView: some View {
        if testing {
            ProgressView(readingCertificate ? "Reading the certificate…" : "Testing…").controlSize(.small)
        } else if let test {
            switch test {
            case .passed(let health, let models):
                Label("Reachable · mirmir \(health.serverVersion) · protocol compatible · \(models) local models", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success).font(.system(size: 12))
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(Palette.danger).font(.system(size: 12))
            }
        } else if kind == .remote, presented != nil, !trusted, !caIssued {
            Label("Trust the certificate, then test again to send the key.", systemImage: "lock.shield")
                .foregroundStyle(Palette.warning).font(.system(size: 12))
        }
    }

    private var readingCertificate: Bool { kind == .remote && !caIssued && presented == nil }

    private var defaultName: String {
        switch kind {
        case .socket: (path as NSString).deletingLastPathComponent.split(separator: "/").last.map(String.init) ?? "Socket"
        case .system: "System"
        case .remote: RemoteEndpoint(address: address)?.host.split(separator: ".").first.map(String.init) ?? "Remote"
        }
    }

    /// The endpoint with the certificate the user trusted, if any.
    private var endpoint: RemoteEndpoint? {
        guard var endpoint = RemoteEndpoint(address: address) else { return nil }
        endpoint.pinnedFingerprint = caIssued ? nil : (trusted ? presented : nil)
        return endpoint
    }

    private var target: InstanceTarget? {
        switch kind {
        case .socket: path.isEmpty ? nil : .socket(path: path)
        case .system: .system
        case .remote: endpoint.map(InstanceTarget.remote)
        }
    }

    /// A remote server is saved only after a passing test, so its pinned
    /// certificate and key are known to work.
    private var canAdd: Bool {
        guard target != nil else { return false }
        if kind != .remote { return true }
        if case .passed = test { return true }
        return false
    }

    private func add() {
        guard let target else { return }
        let record = InstanceRecord(name: name.isEmpty ? defaultName : name, target: target)
        model.add(record, key: kind == .remote ? key.trimmingCharacters(in: .whitespaces) : nil)
        dismiss()
    }

    private func resetCheck() {
        presented = nil
        trusted = false
        test = nil
    }

    private func runTest() {
        guard let target else { return }
        testing = true
        test = nil
        Task {
            defer { testing = false }
            do {
                let connection: RuntimeConnection
                if case .remote(let endpoint) = target {
                    if readingCertificate {
                        presented = try await RuntimeConnection.presentedFingerprint(of: endpoint)
                        return
                    }
                    if !caIssued, !trusted { return }
                    connection = try await RuntimeConnection.connect(remote: endpoint, key: key.trimmingCharacters(in: .whitespaces))
                } else {
                    guard let socket = SocketPaths().socket(for: target) else { return }
                    connection = try await RuntimeConnection.connect(socket: socket)
                }
                let models = (try? await connection.localModels().count) ?? 0
                test = .passed(connection.health, models: models)
                connection.close()
            } catch {
                test = .failed(error.localizedDescription)
            }
        }
    }
}
