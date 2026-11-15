import MirmirKit

/// A row of the models table: a listed model, a download whose checkpoint
/// the server does not list yet, or a Hugging Face search result.
enum ModelRow: Identifiable, Hashable {
    case model(LocalModel)
    case download(ModelDownload)
    case hub(CatalogModel)

    private static let downloadPrefix = "download:"
    private static let hubPrefix = "hub:"

    var id: String {
        switch self {
        case .model(let local): local.selector
        case .download(let download): Self.downloadID(download.repoID)
        case .hub(let result): Self.hubPrefix + result.id
        }
    }

    static func downloadID(_ repoID: String) -> String { downloadPrefix + repoID }

    /// The repository of a download row's id.
    static func downloadRepo(of id: String) -> String? {
        id.hasPrefix(downloadPrefix) ? String(id.dropFirst(downloadPrefix.count)) : nil
    }

    /// The repository of a search result row's id.
    static func hubRepo(of id: String) -> String? {
        id.hasPrefix(hubPrefix) ? String(id.dropFirst(hubPrefix.count)) : nil
    }
}

extension AppModel {
    /// The rows the Models screen lists for `scope` and the search text:
    /// downloads first, then this server's models, then Hugging Face
    /// results that are neither listed nor downloading.
    @MainActor
    func modelRows(scope: ModelScope, query: String, hub: [CatalogModel]) -> [ModelRow] {
        func matches(_ text: String...) -> Bool {
            query.isEmpty || text.contains { $0.localizedCaseInsensitiveContains(query) }
        }
        if scope == .hub { return query.isEmpty ? [] : hub.map(ModelRow.hub) }
        let listed = models
            .filter { local in
                switch scope {
                case .ready: [.available, .loaded].contains(displayState(of: local)) && download(of: local) == nil
                case .downloading: download(of: local) != nil
                case .all, .hub: true
                }
            }
            .filter { matches($0.repoID, $0.selector) }
            .sorted { lhs, rhs in
                let left = displayState(of: lhs) == .loaded, right = displayState(of: rhs) == .loaded
                if left != right { return left }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
        let pending = scope == .ready ? [] : unlistedDownloads.filter { matches($0.repoID) }
        var rows = pending.map(ModelRow.download) + listed.map(ModelRow.model)
        if scope == .all, !query.isEmpty {
            let known = Set(models.map(\.repoID)).union(downloads.keys)
            rows += hub.filter { !known.contains($0.id) }.map(ModelRow.hub)
        }
        return rows
    }
}
