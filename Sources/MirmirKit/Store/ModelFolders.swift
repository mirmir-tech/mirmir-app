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

/// Why a granted folder cannot be read on this launch; the user grants it
/// again to fix it.
public enum FolderAccessFailure: Error, Hashable, Sendable {
    /// The bookmark no longer resolves: the folder or its volume is gone.
    case unresolvable(String)
    /// macOS refused to open the folder's security scope.
    case refused
}

/// The folders granted to the app, persisted with their bookmarks. Access is
/// started on load, before the app starts its server, so a model restored
/// from such a folder is readable. A folder that moved is recorded at its
/// new location, and a stale bookmark is renewed.
@MainActor
@Observable
public final class ModelFolders {
    public private(set) var folders: [ModelFolder]
    /// Granted folders that cannot be read on this launch.
    public private(set) var failures: [UUID: FolderAccessFailure] = [:]
    @ObservationIgnored private let file: JSONFile<[ModelFolder]>
    @ObservationIgnored private var accessed: [UUID: URL] = [:]

    public init(file: JSONFile<[ModelFolder]> = JSONFile(name: "model-folders.json")) {
        self.file = file
        folders = file.load() ?? []
        reopen()
    }

    /// The Hugging Face cache the server lists models from: the first granted
    /// one that is readable.
    public var huggingFaceCache: String? {
        folders.lazy.filter { self.failures[$0.id] == nil }.compactMap { folder -> String? in
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
        if let existing = folders.first(where: { $0.path == url.path }) {
            guard failures[existing.id] != nil else { return existing }
            // Granted again after it could not be opened: a fresh bookmark.
            remove(existing.id)
        }
        let folder = ModelFolder(id: UUID(), path: url.path, kind: ModelFolder.kind(of: url), bookmark: try Self.bookmark(url))
        accessed[folder.id] = url
        folders.append(folder)
        persist()
        return folder
    }

    public func remove(_ id: UUID) {
        guard folders.contains(where: { $0.id == id }) else { return }
        if let url = accessed.removeValue(forKey: id) { Self.stopAccess(url) }
        failures[id] = nil
        folders.removeAll { $0.id == id }
        persist()
    }

    /// Opens every folder's grant and reconciles moved folders and stale
    /// bookmarks into the persisted records.
    private func reopen() {
        var changed = false
        folders = folders.map { folder in
            switch Self.open(folder) {
            case .success(let (url, renewed)):
                accessed[folder.id] = url
                // The same folder spelled through a symlink (`/var`) has not moved.
                let moved = url.resolvingSymlinksInPath().path != URL(fileURLWithPath: folder.path).resolvingSymlinksInPath().path
                guard renewed != nil || moved else { return folder }
                changed = true
                return ModelFolder(id: folder.id, path: url.path, kind: ModelFolder.kind(of: url), bookmark: renewed ?? folder.bookmark)
            case .failure(let failure):
                failures[folder.id] = failure
                return folder
            }
        }
        if changed { persist() }
    }

    /// The folder's current location with its access started, and a renewed
    /// bookmark when macOS reports the stored one as stale.
    private static func open(_ folder: ModelFolder) -> Result<(URL, Data?), FolderAccessFailure> {
        #if os(macOS)
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: folder.bookmark, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch {
            return .failure(.unresolvable(error.localizedDescription))
        }
        guard url.startAccessingSecurityScopedResource() else { return .failure(.refused) }
        return .success((url, stale ? try? bookmark(url) : nil))
        #else
        return .success((URL(fileURLWithPath: folder.path), nil))
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
