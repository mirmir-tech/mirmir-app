import MirmirKit
import SwiftUI

/// Weights + K/V + workspace against the device budget, for the saved
/// context or a candidate one (`pending` while its estimate is on its way).
struct MemoryEstimateView: View {
    let memory: MemoryEstimate
    /// The model's context range; nil for servers before 0.6.1, whose
    /// largest safe context is not meaningful for a loaded model.
    var context: ModelContext?
    var pending = false

    var body: some View {
        let capacity = Double(memory.budgetBytes ?? memory.availableBytes ?? max(memory.requiredBytes, 1))
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Memory at \(Format.grouped(memory.configuredCacheTokens)) tokens").font(.system(size: 12))
                Spacer()
                Text(required).font(.mono(12, weight: .semibold))
            }
            StackedBar(segments: [
                .init(fraction: Double(memory.weightBytes) / capacity, color: Palette.signal),
                .init(fraction: Double(memory.kvCacheBytes) / capacity, color: Palette.brass),
                .init(fraction: Double(memory.workspaceBytes) / capacity, color: Palette.muted.opacity(0.6)),
            ], height: 8)
            Text(breakdown).font(.system(size: 11)).foregroundStyle(.secondary)
            switch memory.fit {
            case .fits:
                if let headroom { Text(headroom).font(.system(size: 11)).foregroundStyle(.secondary) }
            case .doesNotFit:
                Text(["Does not fit the current memory budget.", headroom].compactMap(\.self).joined(separator: " "))
                    .font(.system(size: 11)).foregroundStyle(Palette.danger)
            case .unknown:
                EmptyView()
            }
        }
        .opacity(pending ? 0.55 : 1)
        .animation(.easeOut(duration: 0.15), value: pending)
        .card(padding: 12)
    }

    private var required: String {
        guard let budget = memory.budgetBytes else { return "\(Format.gigabytes(memory.requiredBytes)) GB" }
        return "\(Format.gigabytes(memory.requiredBytes)) of \(Format.gigabytes(budget)) GB"
    }

    private var breakdown: String {
        "\(Format.gigabytes(memory.weightBytes)) GB weights + \(Format.gigabytes(memory.kvCacheBytes)) GB K/V"
            + " + \(Format.gigabytes(memory.workspaceBytes)) GB workspace"
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
        MemoryEstimateView(memory: memory, context: inspection.context).frame(width: 300).padding()
    }
}
#endif
