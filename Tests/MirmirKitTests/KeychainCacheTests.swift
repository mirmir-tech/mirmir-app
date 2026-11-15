import Foundation
import Synchronization
import Testing
@testable import MirmirKit

/// Keychain items in memory, counting reads, refusing them on request.
final class FakeItems: SecretItems {
    struct Store {
        var items: [String: Data] = [:]
        var reads = 0
        var refuses = false
    }

    let store = Mutex(Store())

    func read(_ account: String) throws -> Data? {
        try store.withLock { store in
            store.reads += 1
            if store.refuses { throw CancellationError() }
            return store.items[account]
        }
    }

    func write(_ data: Data, to account: String) throws { store.withLock { $0.items[account] = data } }

    func delete(_ account: String) { store.withLock { _ = $0.items.removeValue(forKey: account) } }

    var reads: Int { store.withLock { $0.reads } }
    var accounts: Set<String> { store.withLock { Set($0.items.keys) } }
}

#if canImport(Security)
@Suite("Keychain prompts")
struct KeychainCacheTests {
    @Test func everyKeyComesFromOneReadPerLaunch() throws {
        let items = FakeItems()
        let (lab, home) = (UUID(), UUID())
        try KeychainCredentials(items: items).setKey("mmk_lab", for: lab)
        try KeychainCredentials(items: items).setKey("mmk_home", for: home)
        let launch = KeychainCredentials(items: items)
        let before = items.reads
        for _ in 0..<20 {
            #expect(launch.key(for: lab) == "mmk_lab")
            #expect(launch.key(for: home) == "mmk_home")
        }
        #expect(items.reads - before == 1)
        #expect(items.accounts == [KeychainCredentials.bundleAccount])
    }

    @Test func aPerServerKeyMovesIntoTheSharedItemOnce() throws {
        let items = FakeItems()
        let lab = UUID()
        try items.write(Data("mmk_old".utf8), to: lab.uuidString)
        let launch = KeychainCredentials(items: items)
        #expect(launch.key(for: lab) == "mmk_old")
        #expect(items.accounts == [KeychainCredentials.bundleAccount])
        #expect(KeychainCredentials(items: items).key(for: lab) == "mmk_old")
        // A server without a key is looked up once, not on every probe.
        let missing = UUID()
        let reads = items.reads
        for _ in 0..<5 { #expect(launch.key(for: missing) == nil) }
        #expect(items.reads - reads == 1)
    }

    @Test func aRefusalIsNotAskedAgainAndNeverOverwritten() throws {
        let items = FakeItems()
        let lab = UUID()
        try KeychainCredentials(items: items).setKey("mmk_lab", for: lab)
        items.store.withLock { $0.refuses = true }
        let launch = KeychainCredentials(items: items)
        let reads = items.reads
        for _ in 0..<10 { #expect(launch.key(for: lab) == nil) }
        #expect(items.reads - reads == 1)
        launch.removeKey(for: UUID())
        #expect(throws: KeychainError.self) { try launch.setKey("mmk_new", for: UUID()) }
        items.store.withLock { $0.refuses = false }
        #expect(KeychainCredentials(items: items).key(for: lab) == "mmk_lab")
    }
}
#endif
