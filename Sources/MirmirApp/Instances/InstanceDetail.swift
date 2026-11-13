import MirmirKit
import SwiftUI

struct InstanceDetail: View {
    @Environment(AppModel.self) private var model
    @State private var managingRemoteAccess = false
    let record: InstanceRecord

    var body: some View {
        let summary = model.summary(for: record)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heading).sectionLabel(Palette.signal)
                    Text(record.name).font(.system(size: 17, weight: .semibold))
                    if case .online(let health) = summary.status {
                        Text("mirmir \(health.serverVersion) · protocol \(health.protocolVersion)")
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                rows(summary)
                if !summary.loadedModels.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Loaded models").font(.system(size: 12, weight: .semibold))
                        ForEach(summary.loadedModels, id: \.self) { selector in
                            HStack(spacing: 8) {
                                StatusDot(color: Palette.signal, size: 6)
                                Text(Conversation.modelName(selector)).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                                    .help(selector)
                            }
                        }
                    }
                    .card(padding: 12)
                }
                actions
                if record.isThisMac { RemoteAccessEntry { managingRemoteAccess = true } }
            }
            .padding(16)
        }
        .sheet(isPresented: $managingRemoteAccess) {
            RemoteAccessSheet(controller: RemoteAccessController(model: model))
        }
    }

    private var heading: String {
        switch record.target {
        case .personal: "LOCAL · bundled runtime"
        case .remote: "REMOTE · gRPC + TLS"
        }
    }

    private func rows(_ summary: InstanceSummary) -> some View {
        VStack(spacing: 0) {
            row("Address", model.address(of: record))
            Divider()
            row("Status", summary.status.label)
            Divider()
            row("Authentication", record.target.kind.isLocal ? "socket permissions" : "API key in the Keychain")
            if case .remote(let endpoint) = record.target {
                Divider()
                row("Certificate", endpoint.pinnedFingerprint.map { "pinned \($0.hex.prefix(23))…" } ?? "system CA")
            }
            if let uptime = summary.telemetry?.uptime {
                Divider()
                row("Uptime", Format.duration(uptime))
            }
            if let device = summary.telemetry?.deviceName, !device.isEmpty {
                Divider()
                row("Device", device)
            }
        }
        .card(padding: 0)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.mono(11)).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
    }

    @ViewBuilder private var actions: some View {
        if record.id == model.currentInstanceID {
            Button("Open Dashboard") { model.section = .overview }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        } else {
            Button("Connect and Open Dashboard") {
                model.select(instance: record.id)
                model.section = .overview
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        if !record.isThisMac {
            Button("Remove Instance", role: .destructive) { model.remove(instance: record.id) }
                .frame(maxWidth: .infinity)
        }
    }
}

/// Opens the Remote Access sheet of This Mac's server.
struct RemoteAccessEntry: View {
    let open: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remote access").font(.system(size: 12, weight: .semibold))
                Text("Let other Macs and the mirmir CLI use this Mac's models over TLS with scoped API keys.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Remote Access…", action: open)
        }
        .padding(10)
        .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
    }
}

#if DEBUG
#Preview("Instance — This Mac", traits: .fixedLayout(width: 340, height: 700)) {
    InstanceDetail(record: .thisMac).previewModel()
}
#Preview("Instance — needs update", traits: .fixedLayout(width: 340, height: 700)) {
    let model = AppModel.preview()
    InstanceDetail(record: model.instances[2]).previewModel(model)
}
#endif
