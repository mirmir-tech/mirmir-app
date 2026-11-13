import AppKit
import MirmirKit
import SwiftUI

/// Remote access to This Mac's server: the TLS listener, its certificate, API
/// keys with their scope and last use, and the clients seen recently.
struct RemoteAccessSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State var controller: RemoteAccessController
    @State private var bind = ""
    @State private var keyName = ""
    @State private var keyScope: RemoteKeyScope = .use

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Remote Access").font(.system(size: 15, weight: .semibold))
                Spacer()
                if controller.working { ProgressView().controlSize(.small) }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    listenerSection
                    if let created = controller.created { CreatedKeyCard(created: created) { controller.dismissCreatedKey() } }
                    keysSection
                    clientsSection
                }
            }
            if let error = controller.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.danger).font(.system(size: 12))
            }
            HStack {
                Text("Keys are managed only on this Mac; no remote key can create or revoke keys.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 620)
        .background(Palette.canvas)
        .task {
            await controller.refresh()
            bind = controller.status?.bind ?? ""
        }
    }

    private var enabled: Binding<Bool> {
        Binding(
            get: { controller.status?.isEnabled ?? false },
            set: { value in Task { await controller.setEnabled(value, bind: bind) } }
        )
    }

    private var listenerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Allow other computers to use this Mac's models", isOn: enabled)
                .disabled(controller.status == nil || controller.working)
            HStack {
                TextField("Listen address", text: $bind, prompt: Text("0.0.0.0:7443")).font(.mono(12))
                Button("Apply") { Task { await controller.setEnabled(true, bind: bind) } }
                    .disabled(controller.working || !(controller.status?.isEnabled ?? false))
            }
            if let listener = controller.status?.listener {
                LabeledContent("Listening", value: listener.address).font(.mono(12))
                if let fingerprint = listener.fingerprint {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listener.certificate == .configured ? "CERTIFICATE SHA-256 · configured" : "CERTIFICATE SHA-256 · self-signed")
                            .sectionLabel(Palette.brass)
                        HStack(alignment: .top) {
                            Text(fingerprint.hex).font(.mono(11)).textSelection(.enabled)
                            Button("Copy Fingerprint") { copy(fingerprint.hex) }
                        }
                        Text("Other Macs show this value when they add the server; it must match.")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
            } else if let error = controller.status?.error {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(Palette.danger).font(.system(size: 12))
            } else if controller.status?.isEnabled == false {
                Text("Remote access is off. Turning it on listens on all interfaces at port 7443 unless you set an address; check the firewall for the networks that should reach it.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .card(padding: 12)
    }

    private var keysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("API KEYS").sectionLabel()
            ForEach(controller.status?.keys ?? []) { key in
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(key.name).font(.system(size: 12, weight: .semibold))
                        Text("\(key.displayPrefix) · \(key.scope?.label ?? "unknown scope") · \(lastUse(key))")
                            .font(.mono(11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { Task { await controller.revoke(key) } }
                }
                Divider()
            }
            if controller.status?.keys.isEmpty ?? true {
                Text("No keys yet.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            HStack {
                TextField("New key name", text: $keyName, prompt: Text("studio-mac"))
                Picker("Scope", selection: $keyScope) {
                    ForEach(RemoteKeyScope.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .frame(width: 160)
                Button("New Key") {
                    Task {
                        await controller.createKey(name: keyName, scope: keyScope)
                        if controller.created != nil { keyName = "" }
                    }
                }
                .disabled(keyName.trimmingCharacters(in: .whitespaces).isEmpty || controller.working)
            }
            Text(keyScope.summary).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .card(padding: 12)
    }

    private var clientsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTED CLIENTS · LAST 15 MIN").sectionLabel()
            let clients = controller.status?.clients ?? []
            if clients.isEmpty {
                Text("No remote client has connected recently.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            ForEach(clients) { client in
                HStack {
                    Text(client.keyName).font(.system(size: 12, weight: .semibold))
                    Text(client.peerAddress.isEmpty ? "—" : client.peerAddress).font(.mono(11)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(client.requests) requests · \(Format.relative(client.lastSeen))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .card(padding: 12)
    }

    private func lastUse(_ key: RemoteKey) -> String {
        key.lastUsedAt.map { "used \(Format.relative($0))" } ?? "unused since the server started"
    }
}

/// The value of a key just created. It is never shown again.
private struct CreatedKeyCard: View {
    let created: CreatedRemoteKey
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("NEW KEY · \(created.key.name.uppercased()) · SHOWN ONCE").sectionLabel(Palette.success)
            HStack(alignment: .top) {
                Text(created.secret).font(.mono(11)).textSelection(.enabled)
                Button("Copy") { copy(created.secret) }
            }
            HStack {
                Text("Paste it into Add Server on the other Mac. The server keeps only its digest.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("I Saved It", action: dismiss)
            }
        }
        .card(padding: 12, fill: Palette.raised)
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
