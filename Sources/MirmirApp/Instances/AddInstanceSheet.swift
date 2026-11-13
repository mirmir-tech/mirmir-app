import MirmirKit
import SwiftUI

/// Adds a remote server and tests it before saving, step by step: its
/// certificate fingerprint first, shown for comparison before any key is
/// sent, then the key and protocol. The sandboxed app reaches no other local
/// socket than its bundled server's, so remote servers are the only kind.
struct AddInstanceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var address = ""
    @State private var key = ""
    @State private var caIssued = false
    @State private var presented: CertificateFingerprint?
    @State private var trusted = false
    @State private var test: RemoteTestResult?
    /// Identifies the test in flight; a completion from an older one, run
    /// with inputs edited since, is discarded.
    @State private var testRun = 0
    @State private var testing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Server").font(.system(size: 15, weight: .semibold))
            Form {
                TextField("Name", text: $name, prompt: Text(defaultName))
                remoteFields
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .onChange(of: address) { resetCheck() }
            .onChange(of: caIssued) { resetCheck() }
            .onChange(of: candidate) { if test?.candidate != candidate { test = nil } }
            testView
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(test == nil ? "Test Connection" : "Test Again", action: runTest)
                    .disabled(RemoteEndpoint(address: address) == nil || testing || key.isEmpty)
                Button("Add Server", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canAdd)
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Palette.canvas)
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
        Text("Create a key on the server with `mirmir remote key create --name <this Mac> --scope use`, or `--scope control` to manage models. The key is stored in your Keychain.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
    }

    @ViewBuilder private var testView: some View {
        if testing {
            ProgressView(readingCertificate ? "Reading the certificate…" : "Testing…").controlSize(.small)
        } else if let test {
            switch test.outcome {
            case .passed(let health, let models):
                Label("Reachable · mirmir \(health.serverVersion) · protocol compatible · \(models) local models", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success).font(.system(size: 12))
            case .failed(let message):
                Label(message, systemImage: "xmark.circle.fill").foregroundStyle(Palette.danger).font(.system(size: 12))
            }
        } else if presented != nil, !trusted, !caIssued {
            Label("Trust the certificate, then test again to send the key.", systemImage: "lock.shield")
                .foregroundStyle(Palette.warning).font(.system(size: 12))
        }
    }

    private var readingCertificate: Bool { !caIssued && presented == nil }

    private var defaultName: String {
        RemoteEndpoint(address: address)?.host.split(separator: ".").first.map(String.init) ?? "Remote"
    }

    /// The current inputs, with the certificate the user trusted, if any.
    private var candidate: RemoteCandidate? {
        RemoteCandidate(address: address, key: key, pinned: caIssued ? nil : (trusted ? presented : nil))
    }

    /// A remote server is saved only after a test passed with exactly these
    /// inputs, so its pinned certificate and key are known to work.
    private var approved: RemoteCandidate? {
        test?.approved(for: candidate, testing: testing)
    }

    private var canAdd: Bool { approved != nil }

    private func add() {
        guard let approved else { return }
        let record = InstanceRecord(name: name.isEmpty ? defaultName : name, target: .remote(approved.endpoint))
        model.add(record, key: approved.key)
        dismiss()
    }

    /// A new address or trust mode needs its certificate read again; any
    /// test in flight is superseded.
    private func resetCheck() {
        presented = nil
        trusted = false
        test = nil
        testRun += 1
        testing = false
    }

    private func runTest() {
        guard let candidate else { return }
        testRun += 1
        let run = testRun
        let readsCertificate = readingCertificate
        testing = true
        test = nil
        Task {
            // Applies a result only while this is the latest test and the
            // inputs are the ones it ran with.
            @MainActor func current() -> Bool { run == testRun && candidate == self.candidate }
            defer { if run == testRun { testing = false } }
            do {
                if readsCertificate {
                    let fingerprint = try await RuntimeConnection.presentedFingerprint(of: candidate.endpoint)
                    if current() { presented = fingerprint }
                    return
                }
                if !caIssued, !trusted { return }
                let connection = try await RuntimeConnection.connect(remote: candidate.endpoint, key: candidate.key)
                let models = (try? await connection.localModels().count) ?? 0
                connection.close()
                if current() { test = RemoteTestResult(candidate: candidate, outcome: .passed(connection.health, models: models)) }
            } catch {
                if current() { test = RemoteTestResult(candidate: candidate, outcome: .failed(error.localizedDescription)) }
            }
        }
    }
}
