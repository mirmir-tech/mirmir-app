import MirmirKit
import SwiftUI

struct ModelInspector: View {
    @Environment(AppModel.self) private var model
    let local: LocalModel

    private var state: LocalModelState { model.displayState(of: local) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                facts
                // Its own view with its own drafts, keyed by the model: a
                // binding into an optional here would be read after a newer
                // selection cleared it, and trap.
                ModelControls(local: local, inspection: model.inspections[local.selector]).id(local.selector)
            }
            .padding(16)
        }
        .task(id: local.selector) { await model.inspect(local.selector) }
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
}

#if DEBUG
#Preview("Inspector — loaded", traits: .fixedLayout(width: 340, height: 800)) {
    let model = AppModel.preview()
    ModelInspector(local: model.models[0]).previewModel(model)
}
#Preview("Inspector — ready", traits: .fixedLayout(width: 340, height: 800)) {
    let model = AppModel.preview()
    ModelInspector(local: model.models[1]).previewModel(model)
}
#Preview("Inspector — over budget", traits: .fixedLayout(width: 340, height: 800)) {
    let model = AppModel.preview()
    ModelInspector(local: model.models[3]).previewModel(model)
}
#endif
