import Foundation
import Observation

/// A folder outside the app's container that the user granted in an open
/// panel. The sandbox lets the bundled server, a child process, read it while
/// the app holds the grant; a security-scoped bookmark keeps the grant across
/// launches.
public struct ModelFolder: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: Hashable, Sendable, Codable {
        /// A Hugging Face cache: `hub` holds `models--owner--name` folders,
        /// which mirmir lists as external models through `HF_HUB_CACHE`.
        case huggingFaceCache(hub: String)
        /// Any other folder; models in it load by path.
        case folder
    }

    public let id: UUID
    public let path: String
    public let kind: Kind
    let bookmark: Data

    /// Recognizes a Hugging Face cache: the hub itself, or an `HF_HOME` that
    /// holds one in `hub`.
    public static func kind(of url: URL) -> Kind {
        func isHub(_ url: URL) -> Bool {
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            return entries.contains { $0.hasPrefix("models--") }
        }
        if isHub(url) { return .huggingFaceCache(hub: url.path) }
        let hub = url.appendingPathComponent("hub")
        if isHub(hub) { return .huggingFaceCache(hub: hub.path) }
        return .folder
    }
}

/// The folders granted to the app, persisted with their bookmarks. Access is
/// started on load, before the app starts its server, so a model restored
/// from such a folder is readable.
@MainActor
@Observable
public final class ModelFolders {
    public private(set) var folders: [ModelFolder]
    @ObservationIgnored private let file: JSONFile<[ModelFolder]>
    @ObservationIgnored private var accessed: [String: URL] = [:]

    public init(file: JSONFile<[ModelFolder]> = JSONFile(name: "model-folders.json")) {
        self.file = file
        folders = file.load() ?? []
        for folder in folders { startAccess(folder) }
    }

    /// The Hugging Face cache the server lists models from: the first granted.
    public var huggingFaceCache: String? {
        folders.lazy.compactMap { folder -> String? in
            if case .huggingFaceCache(let hub) = folder.kind { hub } else { nil }
        }.first
    }

    /// Variables for the server process.
    public var serverEnvironment: [String: String] {
        huggingFaceCache.map { ["HF_HUB_CACHE": $0] } ?? [:]
    }

    /// Grants a folder the user chose in an open panel; the grant is already
    /// active for this launch and the bookmark renews it on the next.
    @discardableResult
    public func add(_ url: URL) throws -> ModelFolder {
        if let existing = folders.first(where: { $0.path == url.path }) { return existing }
        let folder = ModelFolder(id: UUID(), path: url.path, kind: ModelFolder.kind(of: url), bookmark: try Self.bookmark(url))
        accessed[folder.path] = url
        folders.append(folder)
        persist()
        return folder
    }

    public func remove(_ id: UUID) {
        guard let folder = folders.first(where: { $0.id == id }) else { return }
        if let url = accessed.removeValue(forKey: folder.path) { Self.stopAccess(url) }
        folders.removeAll { $0.id == id }
        persist()
    }

    private func startAccess(_ folder: ModelFolder) {
        #if os(macOS)
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: folder.bookmark, options: .withSecurityScope,
                                 relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        accessed[folder.path] = url
        #endif
    }

    private static func bookmark(_ url: URL) throws -> Data {
        #if os(macOS)
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        #else
        Data()
        #endif
    }

    private static func stopAccess(_ url: URL) {
        #if os(macOS)
        url.stopAccessingSecurityScopedResource()
        #endif
    }

    private func persist() {
        try? file.save(folders)
    }
}
