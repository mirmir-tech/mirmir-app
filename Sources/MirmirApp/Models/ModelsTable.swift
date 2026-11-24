import MirmirKit
import SwiftUI

/// This server's models, its running downloads and Hugging Face results in
/// one table. The rows come from `AppModel.modelRows`.
struct ModelsTable: View {
    @Environment(AppModel.self) private var model
    let rows: [ModelRow]
    @Binding var selection: String?
    let choices: VariantChoices
    let download: (String) -> Void

    var body: some View {
        // Cells read the model through this reference, not the environment:
        // AppKit can lay out a cell of a row that is going away outside the
        // view's environment, and an environment read there traps.
        let app = model
        Table(rows, selection: $selection) {
            TableColumn("Name") { row in name(row) }
                .width(min: 180, ideal: 300)
            TableColumn("Features") { row in FeatureChips(features: features(row)) }
                // Room for all three chips; the rest goes to the name.
                .width(min: 215, ideal: 215, max: 240)
            TableColumn("Size") { row in size(row) }
                .width(80)
            TableColumn("Status") { row in status(row, app) }
                .width(min: 120, ideal: 170)
        }
        .alternatingRowBackgrounds(.disabled)
        .paletteBackground()
    }

    private func features(_ row: ModelRow) -> ModelFeatures {
        switch row {
        case .model(let local): local.features
        case .download: []
        case .hub(let result): result.features
        }
    }

    private func name(_ row: ModelRow) -> some View {
        let (title, subtitle): (String, String) = switch row {
        case .model(let local):
            (local.displayName, [local.owner, local.modelClass, local.encoding].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " · "))
        case .download(let download):
            (download.displayName, download.repoID)
        case .hub(let result):
            (result.name, (["Hugging Face", result.owner, result.modelClass, result.quantizations]).filter { !$0.isEmpty }.joined(separator: " · "))
        }
        return VStack(alignment: .leading, spacing: 1) {
            Text(title).fontWeight(.medium)
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.vertical, 3)
    }

    @ViewBuilder private func size(_ row: ModelRow) -> some View {
        switch row {
        case .model(let local):
            Text(Format.bytes(local.sizeBytes)).font(.mono(12))
        case .download(let download):
            Text(download.totalBytes.map(Format.bytes) ?? "—").font(.mono(12)).foregroundStyle(.secondary)
        case .hub(let result):
            // What the chosen quantization needs here, red when it does not fit.
            let variant = choices.variant(of: result)
            let required = variant.map(\.requiredBytes) ?? result.estimatedRequiredBytes
            let fit = variant?.memoryFit ?? result.memoryFit
            Text(required.map(Format.bytes) ?? "—").font(.mono(12))
                .foregroundStyle(fit == .doesNotFit ? Palette.danger : .secondary)
                .help("Memory it needs on this server")
        }
    }

    @ViewBuilder private func status(_ row: ModelRow, _ model: AppModel) -> some View {
        switch row {
        case .model(let local):
            ModelStatus(
                load: model.loads[local.selector], download: model.download(of: local),
                loadability: local.loadability, state: model.displayState(of: local)
            )
        case .download(let download):
            ModelStatus(load: nil, download: download, loadability: .loadable, state: .available)
        case .hub(let result) where result.variants.count > 1:
            HubVariantMenu(result: result, choices: choices, model: model, start: download)
        case .hub(let result):
            let pullID = result.pullID(for: result.defaultChoice)
            HubAction(
                result: result, pullID: pullID, download: model.downloads[pullID],
                downloaded: model.isDownloaded(result), start: download
            )
        }
    }
}

/// A model's status cell. It takes its values from the table rather than
/// reading AppModel from the environment: AppKit can lay out a table cell
/// whose row is going away (a removed or reordered model) outside the
/// view's environment, and an environment read there traps.
struct ModelStatus: View {
    let load: LoadProgress?
    let download: ModelDownload?
    let loadability: Loadability
    let state: LocalModelState

    var body: some View {
        if let load {
            progress(load.fraction, label: load.phase.replacingOccurrences(of: "_", with: " ").capitalized)
        } else if let download {
            // A partial checkpoint is not loadable yet; while its download
            // runs that is progress, not a failure.
            progress(download.fraction, label: download.fraction.map { "\(Int($0 * 100))%" } ?? download.stage)
        } else if case .unavailable(let reason) = loadability {
            Pill(text: reason.isEmpty ? "Unsupported" : reason, color: Palette.danger).help(reason).lineLimit(1)
        } else {
            Pill(text: state.label, color: state.color)
        }
    }

    private func progress(_ fraction: Double?, label: String) -> some View {
        HStack(spacing: 6) {
            if let fraction {
                ProgressView(value: fraction).frame(width: 60)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
