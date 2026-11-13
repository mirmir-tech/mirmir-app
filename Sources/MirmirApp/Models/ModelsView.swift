import AppKit
import MirmirKit
import SwiftUI

enum ModelFilter: String, CaseIterable, Identifiable {
    case all = "All", ready = "Ready", downloads = "Downloads"
    var id: String { rawValue }
}

struct ModelsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var query = ""
    @State private var filter: ModelFilter = .all
    @State private var showInspector = true

    /// The primary model when the table lists it (one loaded from a path
    /// outside the model directories is not listed); else a loaded model that
    /// generates text, then any listed one. A reranker or embedding model has
    /// no generation defaults to show.
    private var initialSelection: String? {
        let models = model.models
        if let primary = model.primaryModel, models.contains(where: { $0.selector == primary.selector }) {
            return primary.selector
        }
        let generates: (LocalModel) -> Bool = { !$0.features.isDisjoint(with: [.tools, .thinking]) }
        let loaded = models.filter { model.displayState(of: $0) == .loaded }
        return (loaded.first(where: generates) ?? models.first(where: generates) ?? loaded.first ?? models.first)?.selector
    }

    /// The sandbox lets the server read a model only from a folder the user
    /// chose; choosing it grants the folder and loads the model in it.
    private func loadFromFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Load"
        panel.message = "Choose a model folder: the one with config.json and the weights"
        if panel.runModal() == .OK, let url = panel.url { model.loadModel(at: url) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if filter == .downloads {
                DownloadsList()
            } else {
                table
            }
        }
        .navigationTitle("Models")
        .navigationSubtitle("\(model.currentInstance.name) · \(model.models.count) models")
        .searchable(text: $query, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem {
                Picker("Filter", selection: $filter) {
                    ForEach(ModelFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button(action: loadFromFolder) { Label("Load from Folder", systemImage: "folder") }
                    .help("Load a model from a folder on this Mac")
            }
            ToolbarItem {
                Button { model.presentingDownload = true } label: { Label("Download", systemImage: "arrow.down.circle") }
            }
            ToolbarItem {
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
            }
        }
        .inspector(isPresented: $showInspector) {
            Group {
                if let selection, let local = model.model(selector: selection) {
                    ModelInspector(local: local)
                } else {
                    EmptyState(title: "No selection", message: "Select a model to inspect it.", symbol: "shippingbox")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.canvas)
            .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        .sheet(isPresented: Bindable(model).presentingDownload) { DownloadSheet() }
        .onAppear { selection = selection ?? initialSelection }
    }

    private var rows: [LocalModel] {
        model.models
            .filter { filter != .ready || [.available, .loaded].contains(model.displayState(of: $0)) }
            .filter { query.isEmpty || $0.repoID.localizedCaseInsensitiveContains(query) || $0.selector.localizedCaseInsensitiveContains(query) }
            .sorted { lhs, rhs in
                let left = model.displayState(of: lhs) == .loaded, right = model.displayState(of: rhs) == .loaded
                if left != right { return left }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn("Name") { local in
                VStack(alignment: .leading, spacing: 1) {
                    Text(local.displayName).fontWeight(.medium)
                    Text([local.owner, local.modelClass, local.encoding].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            }
            TableColumn("Features") { local in FeatureChips(features: local.features) }
                .width(min: 120, ideal: 170)
            TableColumn("Size") { local in Text(Format.bytes(local.sizeBytes)).font(.mono(12)) }
                .width(80)
            TableColumn("Status") { local in ModelStatus(local: local) }
                .width(min: 120, ideal: 170)
        }
        .alternatingRowBackgrounds(.disabled)
        .paletteBackground()
        .overlay {
            if model.models.isEmpty {
                EmptyState(title: "No local models", message: "Download a checkpoint from Hugging Face to get started.", symbol: "shippingbox")
            }
        }
    }
}

struct ModelStatus: View {
    @Environment(AppModel.self) private var model
    let local: LocalModel

    var body: some View {
        if let load = model.loads[local.selector] {
            HStack(spacing: 6) {
                if let fraction = load.fraction {
                    ProgressView(value: fraction).frame(width: 60)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(load.phase.replacingOccurrences(of: "_", with: " ")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else if case .unavailable(let reason) = local.loadability {
            Pill(text: reason.isEmpty ? "Unsupported" : reason, color: Palette.danger).help(reason).lineLimit(1)
        } else {
            Pill(text: model.displayState(of: local).label, color: model.displayState(of: local).color)
        }
    }
}

/// Active Hugging Face transfers.
struct DownloadsList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let transfers = model.transfers.values.sorted { $0.repoID < $1.repoID }
        if transfers.isEmpty {
            EmptyState(title: "No downloads", message: "Downloads started from this app appear here.", symbol: "arrow.down.circle")
        } else {
            List(transfers, id: \.repoID) { transfer in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(transfer.repoID).fontWeight(.medium)
                        Spacer()
                        Text(transfer.phase.label).foregroundStyle(.secondary)
                    }
                    ProgressView(value: transfer.fraction ?? 0)
                    Text(progressText(transfer)).font(.mono(11)).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }
            .paletteBackground()
        }
    }

    private func progressText(_ transfer: TransferProgress) -> String {
        let total = transfer.totalBytes.map { " / \(Format.bytes($0))" } ?? ""
        return "\(Format.bytes(transfer.downloadedBytes))\(total)"
    }
}

#if DEBUG
#Preview("Models", traits: .fixedLayout(width: 1070, height: 800)) {
    NavigationStack { ModelsView() }.previewModel()
}
#endif
