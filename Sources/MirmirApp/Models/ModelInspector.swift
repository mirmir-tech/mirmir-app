import MirmirKit
import SwiftUI

/// A listed model: what it is, what it loads with and its defaults. It
/// re-inspects whenever the model's state changes (loaded, unloaded,
/// downloaded or removed here or by another client).
struct ModelInspector: View {
    @Environment(AppModel.self) private var model
    let local: LocalModel

    private struct Refresh: Hashable {
        let selector: String
        let state: LocalModelState
        let loadability: Loadability
        let downloading: Bool
    }

    private var state: LocalModelState { model.displayState(of: local) }
    private var download: ModelDownload? { model.download(of: local) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorHeader(
                    title: local.displayName,
                    subtitle: [local.repoID, local.shortCommit].filter { !$0.isEmpty }.joined(separator: " · "),
                    features: local.features,
                    state: download == nil ? (state.label, state.color) : ("Downloading", Palette.signal)
                )
                if let download {
                    // A partial checkpoint has nothing to load or inspect yet.
                    DownloadProgressCard(download: download)
                } else if state == .paused {
                    PausedDownloadCard(local: local)
                } else {
                    // Its own view with its own drafts, keyed by the model: a
                    // binding into an optional here would be read after a
                    // newer selection cleared it, and trap.
                    ModelControls(local: local, inspection: model.inspections[local.selector]).id(local.selector)
                }
                details
            }
            .padding(16)
        }
        .task(id: Refresh(selector: local.selector, state: state, loadability: local.loadability, downloading: download != nil)) {
            guard download == nil, state != .paused else { return }
            await model.inspect(local.selector)
        }
    }

    @ViewBuilder private var details: some View {
        if state != .paused { facts }
    }

    private var facts: some View {
        InspectorSection("Model") {
            InspectorRow("Class", value: local.modelClass)
            InspectorRow("Encoding", value: local.encoding ?? "—")
            InspectorRow("Size", value: Format.bytes(local.sizeBytes))
            if let inspection = model.inspections[local.selector], inspection.maxInputTokens > 0 {
                InspectorRow("Max input", value: "\(Format.grouped(inspection.maxInputTokens)) tokens")
            }
        }
    }
}

#if DEBUG
#Preview("Inspector — loaded", traits: .fixedLayout(width: 340, height: 900)) {
    let model = AppModel.preview()
    ModelInspector(local: model.models[0]).previewModel(model)
}
#Preview("Inspector — ready", traits: .fixedLayout(width: 340, height: 900)) {
    let model = AppModel.preview()
    ModelInspector(local: model.models[1]).previewModel(model)
}
#Preview("Inspector — over budget", traits: .fixedLayout(width: 340, height: 900)) {
    let model = AppModel.preview()
    ModelInspector(local: model.models[3]).previewModel(model)
}
#endif
