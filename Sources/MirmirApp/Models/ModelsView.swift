import AppKit
import MirmirKit
import SwiftUI

/// This server's models, their downloads and Hugging Face results in one
/// table. The search field filters the models at once and, in All and
/// Hugging Face, searches the Hub once the text rests; downloading a result
/// returns to the models with its download selected.
struct ModelsView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: String?
    @State private var query = ""
    @State private var hub = HubSearch()
    @State private var choices = VariantChoices()
    @State private var listings = VariantListings()
    @State private var showInspector = true
    /// Bumped to focus the search field.
    @State private var searchFocus = 0

    private var scope: ModelScope { model.modelScope }

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

    /// Whether the search text also searches Hugging Face.
    private var searchesHub: Bool { scope == .all || scope == .hub }

    private var rows: [ModelRow] { model.modelRows(scope: scope, query: query, hub: searchesHub ? hub.results : []) }

    var body: some View {
        let rows = rows
        ModelsTable(rows: rows, selection: $selection, choices: choices, listings: listings, download: download)
            .overlay { if rows.isEmpty { empty } }
            // Finder-like progress over the list, so nothing in the toolbar
            // moves while the Hub is searched.
            .overlay(alignment: .bottom) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Searching Hugging Face…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 16)
                .opacity(searching && !rows.isEmpty ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: searching)
                .allowsHitTesting(false)
            }
        .navigationTitle("Models")
        // The scope tabs and the search field need the toolbar's width; the
        // sidebar already names the screen.
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                ScopeTabs(scope: Bindable(model).modelScope, downloads: model.downloads.count)
                    .fixedSize()
            }
            // The scopes lead; the folder and inspector buttons keep to the
            // trailing edge.
            ToolbarSpacer(.flexible)
            if model.canLoadLocalFolders {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: loadFromFolder) { Label("Load from Folder", systemImage: "folder") }
                        .help("Load a model from a folder on this Mac")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.trailing") }
            }
            // Its own glass capsule, apart from the buttons'.
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                ToolbarSearchField(
                    text: $query, prompt: searchesHub ? "Search models and Hugging Face" : "Filter models",
                    focusRequest: searchFocus
                )
            }
        }
        .inspector(isPresented: $showInspector) {
            inspector
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Palette.canvas)
                .inspectorColumnWidth(min: 300, ideal: 340, max: 420)
        }
        // Keyed by connection and text: switching servers, reconnecting or
        // typing again cancels the pending search and asks the server now
        // connected, whose memory fits and defaults the results carry.
        .task(id: searchesHub ? "\(model.connectionGeneration):\(query)" : "") {
            // Ready and Downloading keep the last results for coming back.
            if searchesHub { await hub.search(query, on: model) }
        }
        .onChange(of: model.currentInstanceID) { _, _ in
            hub.clear()
        }
        // Another server, or this one at a new address or reconnected: its
        // own listings, memory fits and default quantizations.
        .onChange(of: model.connectionGeneration) { _, generation in
            listings.reset(for: generation)
            choices.reset()
        }
        .onChange(of: scope, initial: true) { _, scope in
            if scope == .hub { searchFocus += 1 }
        }
        .onChange(of: rows.map(\.id)) { reselect() }
        .onAppear { selection = selection ?? initialSelection }
    }

    /// Keeps the selection on a shown row: a download's row becomes its
    /// model's once the server lists it, and a filter that hides the
    /// selected row selects the first one shown, so the inspector never
    /// describes a row the table does not show.
    private func reselect() {
        guard let selected = selection else { return }
        let rows = rows
        if rows.contains(where: { $0.id == selected }) { return }
        if let repoID = ModelRow.downloadRepo(of: selected) ?? ModelRow.hubRepo(of: selected),
           let listed = model.models.first(where: { $0.repoID == repoID }) {
            selection = listed.selector
        } else if let repoID = ModelRow.hubRepo(of: selected), model.downloads[repoID] != nil {
            selection = ModelRow.downloadID(repoID)
        } else {
            selection = rows.first?.id
        }
    }

    private var searching: Bool { searchesHub && hub.phase == .searching }

    @ViewBuilder private var empty: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if searchesHub, hub.phase == .waiting || hub.phase == .searching {
            VStack(spacing: 10) {
                ProgressView()
                Text("Searching Hugging Face for “\(trimmed)”…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searchesHub, case .failed(let message) = hub.phase {
            EmptyState(title: "Search failed", message: message, symbol: "exclamationmark.triangle")
        } else if !trimmed.isEmpty {
            EmptyState(
                title: "No matches",
                message: searchesHub ? "Nothing here or on Hugging Face matches “\(trimmed)”." : "No model here matches “\(trimmed)”.",
                symbol: "magnifyingglass"
            )
        } else {
            switch scope {
            case .hub:
                EmptyState(title: "Search Hugging Face", message: "Type a model name, for example mlx-community Qwen3.", symbol: "magnifyingglass")
            case .downloading:
                EmptyState(title: "No downloads", message: "Downloads from any client of this server appear here.", symbol: "arrow.down.circle")
            case .ready:
                EmptyState(title: "No models ready", message: "Downloaded models this server can load appear here.", symbol: "shippingbox")
            case .all:
                EmptyState(title: "No models", message: "Type in the search field to find a model on Hugging Face.", symbol: "shippingbox")
            }
        }
    }

    @ViewBuilder private var inspector: some View {
        if let selection, let local = model.model(selector: selection) {
            ModelInspector(local: local)
        } else if let repoID = selection.flatMap(ModelRow.downloadRepo(of:)), let download = model.downloads[repoID] {
            DownloadInspector(download: download)
        } else if let repoID = selection.flatMap(ModelRow.hubRepo(of:)), let result = hub.results.first(where: { $0.id == repoID }) {
            HubInspector(found: result, choices: choices, listings: listings, download: download)
        } else {
            EmptyState(title: "No selection", message: "Select a model to inspect it.", symbol: "shippingbox")
        }
    }

    /// Starts the download and returns to the models, where its row shows
    /// the progress.
    private func download(_ repoID: String) {
        model.pull(repoID)
        let listed = model.models.first { $0.repoID == repoID }
        selection = listed?.selector ?? ModelRow.downloadID(repoID)
        query = ""
        model.modelScope = .all
    }
}

#if DEBUG
#Preview("Models", traits: .fixedLayout(width: 1070, height: 800)) {
    NavigationStack { ModelsView() }.previewModel()
}
#endif
