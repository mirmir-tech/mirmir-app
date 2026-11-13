import Charts
import MirmirKit
import SwiftUI

/// Loaded model, decode sparkline, prefill/sessions/prefix hits and memory.
struct LiveCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let snapshot = model.telemetry
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LOADED MODEL").sectionLabel(Palette.signal)
                    Text(model.primaryModel?.displayName ?? "No model loaded")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    if let loaded = model.primaryModel {
                        Text([loaded.encoding, loaded.modelClass].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
                    }
                }
                Spacer()
                ModelSwitchMenu()
            }
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Decode").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Metric(value: Format.rate(snapshot?.decode), unit: "tok/s", size: 24)
                }
                Spacer()
                Sparkline(values: model.sparkline).frame(width: 170, height: 44)
            }
            Grid(alignment: .leading, horizontalSpacing: 8) {
                GridRow {
                    small("Prefill", Format.rate(snapshot?.prefill), "t/s")
                    small("Sessions", "\(snapshot?.activeRequests ?? 0)", "active")
                    small("Prefix hits", Format.percent(snapshot?.prefixHitRatio), "%")
                }
            }
            MemoryBlock(snapshot: snapshot)
        }
        .card(padding: 12, radius: 9, fill: Palette.panelCard)
    }

    private func small(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11)).foregroundStyle(Palette.muted)
            Metric(value: value, unit: unit, size: 13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Host memory used vs total, plus K/V block occupancy. The protocol has no
/// per-model weight bytes yet, so weights are not split out.
struct MemoryBlock: View {
    let snapshot: TelemetrySnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Memory").font(.system(size: 11)).foregroundStyle(Palette.muted)
                Spacer()
                if let memory = snapshot?.memory {
                    Text("\(Format.gigabytes(memory.usedBytes)) / \(Format.gigabytes(memory.totalBytes)) GB")
                        .font(.mono(11)).foregroundStyle(Palette.muted)
                }
            }
            StackedBar(segments: [
                .init(fraction: snapshot?.memory?.usedRatio ?? 0, color: (snapshot?.memory?.usedRatio ?? 0) > 0.85 ? Palette.danger : Palette.signal),
            ])
            HStack(spacing: 12) {
                legend(Palette.signal, "Used")
                if let kv = snapshot?.kvUsageRatio {
                    legend(Palette.brass, "K/V blocks \(Format.percent(kv))%")
                }
                if let prefixes = snapshot?.kvCachedPrefixes, prefixes > 0 {
                    legend(Palette.muted, "\(prefixes) cached prefixes")
                }
            }
            .font(.system(size: 10)).foregroundStyle(Palette.muted)
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

struct Sparkline: View {
    let values: [Double]

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { point in
            AreaMark(x: .value("t", point.offset), y: .value("tok/s", point.element))
                .foregroundStyle(Palette.signal.opacity(0.13))
            LineMark(x: .value("t", point.offset), y: .value("tok/s", point.element))
                .foregroundStyle(Palette.signal)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineJoin: .round))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(59, values.count - 1))
        .accessibilityLabel("Decode throughput over the last minute")
    }
}

/// Instance switcher shown under the app name.
struct InstancePicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(model.instances) { record in
                Button(record.name) { model.select(instance: record.id) }
            }
        } label: {
            HStack(spacing: 6) {
                StatusDot(color: model.summary(for: model.currentInstance).status.color)
                Text(label)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 11))
            .foregroundStyle(Palette.muted)
            .contentShape(Rectangle())
        }
        // A plain button keeps the dot and the muted color the borderless
        // menu style would replace with the accent.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var label: String {
        let instance = model.currentInstance
        if case .remote(let endpoint) = instance.target { return "\(instance.name) · \(endpoint.address)" }
        return instance.name
    }
}

/// Load another local model from the panel.
struct ModelSwitchMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu("Switch") {
            ForEach(model.models.filter { $0.loadability == .loadable }) { local in
                Button {
                    model.load(local.selector)
                } label: {
                    Text(model.displayState(of: local) == .loaded ? "✓ \(local.displayName)" : local.displayName)
                }
                .disabled(model.displayState(of: local) == .loaded)
            }
        }
        .controlSize(.small)
        .fixedSize()
    }
}

struct ActivityRow: View {
    @Environment(AppModel.self) private var model
    let activity: Activity

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.kind == .generate ? "bubble.left" : "arrow.down.circle")
                .frame(width: 26, height: 26)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.border, lineWidth: 0.5))
                .foregroundStyle(Palette.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.displayTarget(of: activity))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text([activity.kind.label, activity.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
            }
            Spacer()
            Text(activity.stage).font(.mono(11)).foregroundStyle(activity.isPrefill ? Palette.brass : Palette.signal)
        }
    }
}
