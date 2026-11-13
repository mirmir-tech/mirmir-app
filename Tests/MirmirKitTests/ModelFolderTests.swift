import Foundation
import Testing
@testable import MirmirKit

@Suite("Model folders")
@MainActor
struct ModelFolderTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func recognizesHuggingFaceCaches() throws {
        let home = try scratch()
        defer { try? FileManager.default.removeItem(at: home) }
        let hub = home.appendingPathComponent("hub")
        try FileManager.default.createDirectory(at: hub.appendingPathComponent("models--Qwen--Qwen3-4B"), withIntermediateDirectories: true)
        let plain = home.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)

        #expect(ModelFolder.kind(of: home) == .huggingFaceCache(hub: hub.path))
        #expect(ModelFolder.kind(of: hub) == .huggingFaceCache(hub: hub.path))
        #expect(ModelFolder.kind(of: plain) == .folder)
    }

    @Test func aGrantedCacheReachesTheServerAndPersists() throws {
        let home = try scratch(), store = try scratch()
        defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: store) }
        try FileManager.default.createDirectory(at: home.appendingPathComponent("hub/models--a--b"), withIntermediateDirectories: true)
        let file = JSONFile<[ModelFolder]>(name: "model-folders.json", directory: store)

        let folders = ModelFolders(file: file)
        #expect(folders.serverEnvironment.isEmpty)
        let added = try folders.add(home)
        #expect(try folders.add(home) == added)
        #expect(folders.serverEnvironment == ["HF_HUB_CACHE": home.appendingPathComponent("hub").path])

        let reloaded = ModelFolders(file: file)
        #expect(reloaded.folders.map(\.path) == [home.path])
        reloaded.remove(added.id)
        #expect(reloaded.serverEnvironment.isEmpty)
        #expect(ModelFolders(file: file).folders.isEmpty)
    }

    // Following a move and reporting a missing folder are what Darwin's
    // bookmarks do; swift-corelibs-foundation's bookmarks are plain paths.
    #if canImport(Darwin)
    @Test func aMovedCacheIsFollowedAndAMissingOneIsReported() throws {
        let root = try scratch(), store = try scratch()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: store) }
        let original = root.appendingPathComponent("huggingface")
        let gone = root.appendingPathComponent("gone")
        try FileManager.default.createDirectory(at: original.appendingPathComponent("hub/models--a--b"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        let file = JSONFile<[ModelFolder]>(name: "model-folders.json", directory: store)
        let folders = ModelFolders(file: file)
        let cache = try folders.add(original)
        let missing = try folders.add(gone)

        let moved = root.appendingPathComponent("renamed")
        try FileManager.default.moveItem(at: original, to: moved)
        try FileManager.default.removeItem(at: gone)
        let reloaded = ModelFolders(file: file)
        func real(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

        let followed = try #require(reloaded.folders.first { $0.id == cache.id })
        #expect(real(followed.path) == real(moved.path))
        #expect(reloaded.serverEnvironment["HF_HUB_CACHE"].map(real) == real(moved.appendingPathComponent("hub").path))
        #expect(reloaded.failures[cache.id] == nil)
        #expect(reloaded.failures[missing.id] != nil)
        // The move is persisted for the next launch.
        #expect(ModelFolders(file: file).folders.first { $0.id == cache.id }.map { real($0.path) } == real(moved.path))
    }
    #endif

        @Test func onlyTheBundledServerIsUsed() {
        #expect(ServerBinary.resolve(bundle: Bundle(for: BundleMarker.self)) == nil)
        #expect(ServerBinary.bundled(in: .main).path.hasSuffix("Contents/Helpers/mirmir"))
    }
}

private final class BundleMarker {}

@Suite("Bundled server configuration")
struct ServerConfigurationTests {
    @Test func configFileResolvesLikeMirmir() {
        #expect(SocketPaths(environment: ["HOME": "/h"]).configFile == "/h/.config/mirmir/config.toml")
        #expect(SocketPaths(environment: ["HOME": "/h", "XDG_CONFIG_HOME": "/x"]).configFile == "/x/mirmir/config.toml")
        #expect(SocketPaths(environment: ["HOME": "/h", "MIRMIR_CONFIG_HOME": "/c"]).configFile == "/c/config.toml")
    }

    @Test func theAppsServerAvoidsMirmirsDefaultPort() {
        #expect(ServerSupervisor.httpBind != "127.0.0.1:8080")
    }
}
