import MirmirKit
import SwiftUI

/// The current server's configuration, as mirmir's TUI and dashboard show
/// it: its two secrets, then one card per part of the server. Every change
/// goes to the server, which validates it and saves it in its config.toml.
struct ConfigurationView: View {
    @Environment(AppModel.self) private var model
    @State private var controller: ConfigurationController?

    var body: some View {
        Group {
            if let controller {
                ConfigurationContent(controller: controller)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if controller == nil { controller = ConfigurationController(model: model) } }
    }
}

enum ConfigurationFilter: Hashable, CaseIterable {
    case all, overridden
}

struct ConfigurationCard: Identifiable {
    let category: SettingCategory
    let entries: [ConfigurationEntry]

    var id: SettingCategory { category }
}

struct ConfigurationContent: View {
    @Environment(AppModel.self) private var model
    let controller: ConfigurationController
    @State private var query = ""
    @State private var filter: ConfigurationFilter = .all

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                banners
                if let configuration = controller.configuration {
                    if query.isEmpty, filter == .all { secrets(configuration) }
                    let cards = visibleCards(configuration)
                    ForEach(cards) { card in
                        CategoryCard(category: card.category, entries: card.entries, busy: controller.working) { key, value in
                            Task { await controller.apply(.set(key: key, value: value)) }
                        }
                    }
                    if cards.isEmpty { nothingMatches }
                    if let files = configuration.files {
                        Text("Saved in \(files.config)").font(.mono(10)).foregroundStyle(Palette.muted)
                            .textSelection(.enabled).padding(.horizontal, 4)
                    }
                } else if controller.working {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
            }
            .padding(20)
            .frame(maxWidth: 980)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Configuration")
        .navigationSubtitle(subtitle)
        .searchable(text: $query, placement: .toolbar, prompt: "Search settings")
        .toolbar {
            ToolbarItem {
                Picker("Show", selection: $filter) {
                    Text("All").tag(ConfigurationFilter.all)
                    Text("Overridden").tag(ConfigurationFilter.overridden)
                }
                .pickerStyle(.segmented)
            }
        }
        .task(id: refreshKey) { await controller.refresh() }
    }

    /// Reads the settings again for another server or a new connection.
    private var refreshKey: String {
        let connection = model.connection.map { "\(ObjectIdentifier($0).hashValue)" } ?? "none"
        return "\(model.currentInstanceID.uuidString)-\(connection)"
    }

    private var subtitle: String {
        guard let configuration = controller.configuration else { return model.currentInstance.name }
        let overridden = configuration.entries.filter(\.isOverridden).count
        return "\(model.currentInstance.name) · \(overridden) overridden of \(configuration.entries.count)"
    }

    @ViewBuilder private var banners: some View {
        if controller.restartPending {
            Banner(symbol: "arrow.clockwise.circle.fill", color: Palette.warning,
                   text: "Saved. Some changes take effect when \(model.currentInstance.name) restarts.") {
                if controller.canRestartServer {
                    Button("Restart Server") { controller.restartServer() }.buttonStyle(.borderedProminent).controlSize(.small)
                } else {
                    Text("Restart it where it runs.").font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
            }
        }
        if let error = controller.error {
            Banner(symbol: "exclamationmark.triangle.fill", color: Palette.danger, text: error) {
                Button("Dismiss") { controller.clearError() }.controlSize(.small)
            }
        }
        if let message = controller.message {
            Banner(symbol: "checkmark.circle.fill", color: Palette.success, text: message) { EmptyView() }
        }
    }

    private func secrets(_ configuration: ServerConfiguration) -> some View {
        HStack(alignment: .top, spacing: 14) {
            SecretTile(
                label: "HUGGING FACE TOKEN", symbol: "key.fill",
                help: "Downloads gated models whose terms you accepted on Hugging Face.",
                state: configuration.huggingFaceToken, busy: controller.working,
                save: { token in Task { await controller.apply(.setHuggingFaceToken(token)) } },
                remove: { Task { await controller.apply(.removeHuggingFaceToken) } },
                test: { Task { await controller.apply(.testHuggingFaceToken) } }
            )
            SecretTile(
                label: "HTTP API KEY", symbol: "lock.fill",
                help: "Clients of the OpenAI-compatible API must send it as a bearer token.",
                state: configuration.httpAPIKey, busy: controller.working,
                save: { key in Task { await controller.apply(.setHTTPAPIKey(key)) } },
                remove: { Task { await controller.apply(.removeHTTPAPIKey) } }
            )
        }
        // Both tiles as tall as the taller one, and no taller.
        .fixedSize(horizontal: false, vertical: true)
    }

    private var nothingMatches: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(Palette.muted)
            Text(filter == .overridden && query.isEmpty
                 ? "Every setting uses mirmir's default."
                 : "No setting matches “\(query)”.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 50)
    }

    /// The entries of each category that pass the filter and the search.
    private func visibleCards(_ configuration: ServerConfiguration) -> [ConfigurationCard] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        let shown = configuration.entries.filter { entry in
            guard filter == .all || entry.isOverridden else { return false }
            guard !needle.isEmpty else { return true }
            let description = SettingCatalog.describe(entry.key)
            return [entry.key, description.title, description.help, entry.value]
                .contains { $0.lowercased().contains(needle) }
        }
        return SettingCategory.allCases.compactMap { category in
            let entries = shown.filter { SettingCatalog.describe($0.key).category == category }
            return entries.isEmpty ? nil : ConfigurationCard(category: category, entries: entries)
        }
    }
}

#if DEBUG
#Preview("Configuration") {
    let model = AppModel.preview(.connected)
    return ConfigurationContent(controller: .preview(model)).previewModel(model).frame(width: 900, height: 900)
}

#Preview("Restart pending") {
    let model = AppModel.preview(.connected)
    return ConfigurationContent(controller: .preview(model, restartPending: true)).previewModel(model).frame(width: 900, height: 700)
}
#endif
