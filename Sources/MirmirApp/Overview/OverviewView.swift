import Charts
import MirmirKit
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                KPIRow(snapshot: model.telemetry)
                HStack(alignment: .top, spacing: 14) {
                    ThroughputChart(samples: model.history.samples)
                        .frame(maxWidth: .infinity)
                    MemoryChart(samples: model.history.samples)
                        .frame(width: 380)
                }
                RetentionNote(history: model.history, range: model.range)
                SessionsCard(activities: Array(model.recentOperations.prefix(8)))
            }
            .padding(20)
        }
        .navigationTitle("Overview")
        .navigationSubtitle(subtitle)
        .toolbar {
            ToolbarItem {
                Picker("Time range", selection: $model.range) {
                    ForEach(TimeRange.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem { LoadModelMenu() }
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let loaded = model.primaryModel {
            parts.append(loaded.displayName)
            if !loaded.encoding.isEmpty { parts.append(loaded.encoding) }
        } else {
            parts.append("No model loaded")
        }
        if let uptime = model.telemetry?.uptime { parts.append("up \(Format.duration(uptime))") }
        return parts.joined(separator: " · ")
    }
}

struct KPIRow: View {
    let snapshot: TelemetrySnapshot?

    var body: some View {
        HStack(spacing: 14) {
            tile("DECODE", Palette.signal, Format.rate(snapshot?.decode), "tok/s",
                 note: "mean \(Format.rate(snapshot?.meanDecode)) · \(snapshot?.activeRequests ?? 0) active")
            tile("PREFILL", Palette.brass, Format.rate(snapshot?.prefill), "tok/s",
                 note: "mean \(Format.rate(snapshot?.meanPrefill))")
            tile("TTFT", Palette.muted, Format.seconds(fromMilliseconds: snapshot?.currentTTFTMs ?? snapshot?.lastTTFTMs), "s",
                 note: "mean \(Format.seconds(fromMilliseconds: snapshot?.meanTTFTMs)) s · \(Format.grouped(snapshot?.totalRequests ?? 0)) requests")
            tile("MEMORY", Palette.muted, snapshot?.memory.map { Format.gigabytes($0.usedBytes) } ?? "—", "GB",
                 note: snapshot?.memory.map { "\(Format.percent($0.usedRatio))% of \(Format.gigabytes($0.totalBytes)) GB · \($0.source)" } ?? "not reported")
        }
    }

    private func tile(_ label: String, _ color: Color, _ value: String, _ unit: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).sectionLabel(color)
            Metric(value: value, unit: unit, size: 26)
            Text(note).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

struct ThroughputChart: View {
    let samples: [TelemetrySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Throughput").font(.system(size: 13, weight: .semibold))
                Spacer()
                legend(Palette.signal, "Decode")
                legend(Palette.brass, "Prefill")
                legend(Palette.muted, "Active requests")
            }
            if samples.isEmpty {
                EmptyState(title: "No samples yet", message: "The server records a sample every second.", symbol: "chart.xyaxis.line")
            } else {
                Chart {
                    ForEach(samples) { sample in
                        AreaMark(x: .value("Time", sample.sampledAt), y: .value("tok/s", sample.decode ?? 0), series: .value("s", "decode-area"))
                            .foregroundStyle(Palette.signal.opacity(0.12))
                        LineMark(x: .value("Time", sample.sampledAt), y: .value("tok/s", sample.decode ?? 0), series: .value("s", "Decode"))
                            .foregroundStyle(Palette.signal)
                            .lineStyle(StrokeStyle(lineWidth: 1.6))
                    }
                    ForEach(samples.filter { $0.prefill != nil }) { sample in
                        PointMark(x: .value("Time", sample.sampledAt), y: .value("tok/s", min(sample.prefill ?? 0, peakDecode * 1.5)))
                            .foregroundStyle(Palette.brass)
                            .symbolSize(10)
                    }
                    ForEach(samples) { sample in
                        LineMark(x: .value("Time", sample.sampledAt), y: .value("tok/s", Double(sample.activeRequests) * requestScale), series: .value("s", "Active"))
                            .foregroundStyle(Palette.muted)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .interpolationMethod(.stepEnd)
                    }
                }
                .chartYAxisLabel("tok/s")
            }
        }
        .frame(height: 280)
        .card()
    }

    /// Prefill rates dwarf decode; clamp the dots so decode stays readable.
    private var peakDecode: Double { max(samples.compactMap(\.decode).max() ?? 1, 1) }

    /// Request counts share the decode axis, scaled so the peak count sits at
    /// a quarter of the peak decode rate.
    private var requestScale: Double {
        let peak = Double(samples.map(\.activeRequests).max() ?? 1)
        return peak == 0 ? 1 : peakDecode * 0.25 / peak
    }
}

struct MemoryChart: View {
    let samples: [TelemetrySample]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Memory").font(.system(size: 13, weight: .semibold))
                Spacer()
                if let memory = samples.last?.memory {
                    Text("\(memory.source) · limit \(Format.gigabytes(memory.totalBytes)) GB")
                        .font(.mono(11)).foregroundStyle(Palette.muted).lineLimit(1)
                }
            }
            let readings = samples.compactMap { sample in sample.memory.map { (sample.sampledAt, $0) } }
            if readings.isEmpty {
                EmptyState(title: "Not reported", message: "This server does not report host memory.", symbol: "memorychip")
            } else {
                Chart {
                    ForEach(readings, id: \.0) { date, memory in
                        AreaMark(x: .value("Time", date), y: .value("GB", Double(memory.usedBytes) / 1e9))
                            .foregroundStyle(Palette.signal.opacity(0.35))
                    }
                    if let total = readings.last?.1.totalBytes {
                        RuleMark(y: .value("Limit", Double(total) / 1e9))
                            .foregroundStyle(Palette.danger)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartYAxisLabel("GB")
            }
        }
        .frame(height: 280)
        .card()
    }
}

private func legend(_ color: Color, _ text: String) -> some View {
    HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
        Text(text).font(.system(size: 11)).foregroundStyle(Palette.muted)
    }
}

/// Tells the reader when the chosen range exceeds what the server retains.
struct RetentionNote: View {
    let history: TelemetryHistory
    let range: TimeRange

    var body: some View {
        let retained = Double(history.retentionLimit) * history.samplingInterval
        if history.retentionLimit > 0, retained < range.duration {
            Text("The server keeps \(history.retentionLimit) samples (\(Format.duration(retained))); older data is not available.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted)
        }
    }
}
