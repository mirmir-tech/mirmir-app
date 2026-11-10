import MirmirKit
import SwiftUI

struct InstancesView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: UUID?
    @State private var adding = false

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: 14)], spacing: 14) {
                ForEach(model.instances) { record in
                    InstanceCard(record: record, selected: record.id == (selection ?? model.currentInstanceID))
                        .onTapGesture { selection = record.id }
                        .onTapGesture(count: 2) { model.select(instance: record.id) }
                }
            }
            .padding(20)
        }
        .navigationTitle("Instances")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Button { adding = true } label: { Label("Add Server", systemImage: "plus") }
            }
        }
        .inspector(isPresented: .constant(true)) {
            if let record = model.instances.first(where: { $0.id == (selection ?? model.currentInstanceID) }) {
                InstanceDetail(record: record)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.canvas)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
            }
        }
        .sheet(isPresented: $adding) { AddInstanceSheet() }
    }

    private var subtitle: String {
        let statuses = model.instances.map { model.summary(for: $0).status }
        let online = statuses.filter { if case .online = $0 { true } else { false } }.count
        let update = statuses.filter { if case .updateNeeded = $0 { true } else { false } }.count
        var text = "\(model.instances.count) instances · \(online) online"
        if update > 0 { text += " · \(update) need an update" }
        return text
    }
}

struct InstanceCard: View {
    @Environment(AppModel.self) private var model
    let record: InstanceRecord
    let selected: Bool

    var body: some View {
        let summary = model.summary(for: record)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: record.isThisMac ? "laptopcomputer" : "server.rack")
                    .frame(width: 34, height: 34)
                    .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(record.name).font(.system(size: 14, weight: .semibold))
                        Pill(text: summary.status.label, color: summary.status.color)
                        if record.id == model.currentInstanceID { Pill(text: "Current", color: Palette.signal) }
                    }
                    Text(model.address(of: record)).font(.mono(11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 12) {
                GridRow {
                    stat("Loaded model", summary.loadedModels.first.map { $0.split(separator: "/").last.map(String.init) ?? $0 } ?? "—")
                    stat("Decode", summary.telemetry.map { "\(Format.rate($0.decode)) t/s" } ?? "—")
                    stat("Sessions", summary.telemetry.map { "\($0.activeRequests)" } ?? "—")
                }
            }
            if let memory = summary.telemetry?.memory {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Memory").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Format.gigabytes(memory.usedBytes)) / \(Format.gigabytes(memory.totalBytes)) GB").font(.mono(11))
                    }
                    StackedBar(segments: [.init(fraction: memory.usedRatio, color: memory.usedRatio > 0.85 ? Palette.danger : Palette.signal)])
                }
            }
            if let notice = notice(summary.status) {
                Text(notice).font(.system(size: 11)).foregroundStyle(Palette.muted)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.soft(summary.status.color, 0.1), in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(14)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.signal : Palette.border, lineWidth: selected ? 1 : 0.5))
        .opacity(summary.status.isOffline ? 0.8 : 1)
        .contentShape(Rectangle())
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value).font(.mono(12, weight: .medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func notice(_ status: InstanceStatus) -> String? {
        switch status {
        case .updateNeeded(let server, let version):
            "Server protocol \(server) (mirmir \(version)) differs from this app. Update mirmir on the server."
        case .offline(let reason):
            reason
        case .checking, .online:
            nil
        }
    }
}

extension InstanceStatus {
    var isOffline: Bool {
        if case .offline = self { true } else { false }
    }
}

extension AppModel {
    func address(of record: InstanceRecord) -> String {
        if case .remote(let endpoint) = record.target { return "grpcs://\(endpoint.address)" }
        let socket = SocketPaths().socket(for: record.target) ?? ""
        return socket.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
