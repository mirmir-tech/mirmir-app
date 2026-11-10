import MirmirKit
import SwiftUI

struct ModelInspector: View {
    @Environment(AppModel.self) private var model
    let local: LocalModel
    @State private var settings: GenerationSettings?
    @State private var saving = false

    private var state: LocalModelState { model.displayState(of: local) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                facts
                if let memory = model.inspections[local.selector]?.memory {
                    MemoryEstimateView(memory: memory)
                }
                if settings != nil { settingsForm }
                actions
            }
            .padding(16)
        }
        .task(id: local.selector) {
            settings = nil
            await model.inspect(local.selector)
            settings = model.inspections[local.selector]?.settings
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.label.uppercased()).sectionLabel(state.color)
            Text(local.displayName).font(.system(size: 17, weight: .semibold))
            Text([local.repoID, local.shortCommit].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.mono(11)).foregroundStyle(.secondary).textSelection(.enabled)
            FeatureChips(features: local.features, long: true).padding(.top, 4)
        }
    }

    private var facts: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                fact("Class", local.modelClass)
                fact("Encoding", local.encoding)
            }
            GridRow {
                fact("Size", Format.bytes(local.sizeBytes))
                fact("Max input", model.inspections[local.selector].map { Format.grouped($0.maxInputTokens) } ?? "—")
            }
        }
        .card(padding: 12)
    }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value.isEmpty ? "—" : value).font(.mono(12, weight: .medium)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var settingsForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generation defaults").font(.system(size: 12, weight: .semibold))
            if let binding = Binding($settings) {
                Form {
                    TextField("Max tokens", value: binding.maxTokens, format: .number)
                    LabeledContent("Temperature") {
                        Slider(value: binding.temperature, in: 0...2, step: 0.05)
                        Text(String(format: "%.2f", binding.wrappedValue.temperature)).font(.mono(11)).frame(width: 36)
                    }
                    LabeledContent("Top P") {
                        Slider(value: binding.topP, in: 0...1, step: 0.01)
                        Text(String(format: "%.2f", binding.wrappedValue.topP)).font(.mono(11)).frame(width: 36)
                    }
                    Stepper("Top K: \(binding.wrappedValue.topK)", value: binding.topK, in: 0...500)
                    TextField("Repetition penalty", value: binding.repetitionPenalty, format: .number.precision(.fractionLength(2)))
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -16)
                HStack {
                    Spacer()
                    Button("Save Defaults") {
                        guard let settings else { return }
                        saving = true
                        Task {
                            await model.updateSettings(local.selector, settings)
                            saving = false
                        }
                    }
                    .disabled(saving || settings == model.inspections[local.selector]?.settings)
                }
            }
        }
    }

    private var actions: some View {
        HStack {
            if state == .loaded {
                Button("Unload", role: .destructive) { model.unload(model.servingSelector(for: local)) }
            } else {
                Button("Load") { model.load(local.selector) }
                    .buttonStyle(.borderedProminent)
                    .disabled(local.loadability != .loadable || model.loads[local.selector] != nil)
            }
            Spacer()
            if local.managed, state != .loaded, !local.repoID.isEmpty {
                Button("Remove from Disk", role: .destructive) { model.removeCheckpoint(local.repoID) }
            }
        }
    }
}

/// Weights + K/V + workspace against the device budget.
struct MemoryEstimateView: View {
    let memory: MemoryEstimate

    var body: some View {
        let capacity = Double(memory.budgetBytes ?? memory.availableBytes ?? max(memory.requiredBytes, 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Memory at \(Format.grouped(memory.configuredCacheTokens)) tokens").font(.system(size: 12))
                Spacer()
                Text("\(Format.gigabytes(memory.requiredBytes)) GB").font(.mono(12, weight: .semibold))
            }
            StackedBar(segments: [
                .init(fraction: Double(memory.weightBytes) / capacity, color: Palette.signal),
                .init(fraction: Double(memory.kvCacheBytes) / capacity, color: Palette.brass),
                .init(fraction: Double(memory.workspaceBytes) / capacity, color: Palette.muted.opacity(0.6)),
            ], height: 8)
            Text(caption).font(.system(size: 11)).foregroundStyle(.secondary)
            if memory.fit == .doesNotFit {
                Text("Does not fit the current memory budget.").font(.system(size: 11)).foregroundStyle(Palette.danger)
            }
        }
        .card(padding: 12)
    }

    private var caption: String {
        var text = "\(Format.gigabytes(memory.weightBytes)) weights + \(Format.gigabytes(memory.kvCacheBytes)) K/V"
        if let budget = memory.budgetBytes { text += " of \(Format.gigabytes(budget)) GB budget" }
        if let safe = memory.maxSafeContextTokens { text += " · safe up to \(Format.grouped(safe)) tokens" }
        return text
    }
}
