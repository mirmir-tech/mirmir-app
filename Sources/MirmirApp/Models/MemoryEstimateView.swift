import MirmirKit
import SwiftUI

/// Weights + K/V + workspace against the device budget, for the saved
/// context or a candidate one (`pending` while its estimate is on its way).
/// Its container frames it: the context card, or a Memory section.
struct MemoryEstimateView: View {
    let memory: MemoryEstimate
    /// The model's context range; nil for servers before 0.6.1, whose
    /// largest safe context is not meaningful for a loaded model.
    var context: ModelContext?
    var pending = false

    var body: some View {
        let capacity = Double(memory.budgetBytes ?? memory.availableBytes ?? max(memory.requiredBytes, 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Memory").font(.system(size: 12))
                Spacer()
                Text(required).font(.mono(12, weight: .semibold))
                    .foregroundStyle(memory.fit.color ?? .primary)
            }
            StackedBar(segments: Part.allCases.map { .init(fraction: Double($0.bytes(memory)) / capacity, color: $0.color) }, height: 8)
            // One line when it fits, else one part per line; never a part
            // broken across lines.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { legend }
                VStack(alignment: .leading, spacing: 2) { legend }
            }
            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
            switch memory.fit {
            case .fits:
                if let headroom { InspectorNote(headroom) }
            case .tight:
                InspectorNote(["Fits, with little of the memory budget to spare.", headroom].compactMap(\.self).joined(separator: " "), color: Palette.warning)
            case .doesNotFit:
                InspectorNote(["Does not fit the current memory budget.", headroom].compactMap(\.self).joined(separator: " "), color: Palette.danger)
            case .unknown:
                EmptyView()
            }
        }
        .opacity(pending ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: pending)
    }

    private var legend: some View {
        ForEach(Part.allCases, id: \.self) { part in
            HStack(spacing: 4) {
                Circle().fill(part.color).frame(width: 6, height: 6)
                Text("\(part.label) \(Format.gigabytes(part.bytes(memory))) GB")
            }
            .fixedSize()
        }
    }

    private enum Part: CaseIterable {
        case weights, cache, workspace

        var label: String {
            switch self {
            case .weights: "Weights"
            case .cache: "K/V"
            case .workspace: "Workspace"
            }
        }

        var color: Color {
            switch self {
            case .weights: Palette.signal
            case .cache: Palette.brass
            case .workspace: Palette.muted.opacity(0.6)
            }
        }

        func bytes(_ memory: MemoryEstimate) -> UInt64 {
            switch self {
            case .weights: memory.weightBytes
            case .cache: memory.kvCacheBytes
            case .workspace: memory.workspaceBytes
            }
        }
    }

    private var required: String {
        guard let budget = memory.budgetBytes else { return "\(Format.gigabytes(memory.requiredBytes)) GB" }
        return "\(Format.gigabytes(memory.requiredBytes)) of \(Format.gigabytes(budget)) GB"
    }

    /// The largest context that fits the budget, when the server reports a
    /// meaningful one.
    private var headroom: String? {
        guard let context, let safe = memory.maxSafeContextTokens, safe >= context.minTokens else { return nil }
        if safe >= context.maxTokens { return "The model's full \(Format.grouped(context.maxTokens))-token context fits." }
        return "Up to \(Format.grouped(safe)) tokens fit."
    }
}

#if DEBUG
#Preview("Memory estimate — over budget", traits: .sizeThatFitsLayout) {
    let model = AppModel.preview()
    if let inspection = model.inspections[model.models[3].selector], let memory = inspection.memory {
        MemoryEstimateView(memory: memory, context: inspection.context).frame(width: 300).card(padding: 12).padding()
    }
}
#endif
