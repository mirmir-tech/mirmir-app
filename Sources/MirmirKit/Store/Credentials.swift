import Foundation
import Synchronization

#if canImport(Security)
import Security
#endif

/// Remote API keys, one per saved instance. Keys never go into
/// `instances.json`; on macOS they live in the login Keychain.
public protocol CredentialStore: Sendable {
    func key(for instance: UUID) -> String?
    func setKey(_ key: String, for instance: UUID) throws
    func removeKey(for instance: UUID)
}

public enum Credentials {
    /// The Keychain on macOS; memory elsewhere, for tests and Linux builds.
    public static var platformDefault: any CredentialStore {
        #if canImport(Security)
        KeychainCredentials()
        #else
        MemoryCredentials()
        #endif
    }
}

public final class MemoryCredentials: CredentialStore {
    private let keys = Mutex<[UUID: String]>([:])

    public init() {}

    public func key(for instance: UUID) -> String? { keys.withLock { $0[instance] } }

    public func setKey(_ key: String, for instance: UUID) throws { keys.withLock { $0[instance] = key } }

    public func removeKey(for instance: UUID) { keys.withLock { _ = $0.removeValue(forKey: instance) } }
}

/// What `KeychainCredentials` reads and writes: generic password items of
/// one service, by account. A protocol so tests can count reads and refuse
/// them as a user who clicks Deny would.
public protocol SecretItems: Sendable {
    /// The item's data; nil when there is none; throws when it is refused.
    func read(_ account: String) throws -> Data?
    func write(_ data: Data, to account: String) throws
    func delete(_ account: String)
}

#if canImport(Security)
/// Every remote API key in one item, read once per launch and kept in
/// memory. Each read of a login Keychain item another build of the app
/// created asks the user, so reading a key per connection (every probe of
/// every server, every 10 s) asked again and again; this asks at most once.
/// Keys from before 0.6.1, one item per server, move into it when first
/// needed.
public final class KeychainCredentials: CredentialStore {
    static let service = "tech.mirmir.app.remote-key"
    /// The account of the item holding every key.
    static let bundleAccount = "keys"

    private enum State {
        case unread
        case read([UUID: String])
        /// The user refused the Keychain: no further prompts this launch,
        /// and nothing is written over the item.
        case refused
    }

    private struct Cache {
        var state = State.unread
        /// Servers whose pre-0.6.1 item was looked for.
        var looked: Set<UUID> = []
    }

    private let items: any SecretItems
    private let cache = Mutex(Cache())

    public init(items: any SecretItems = defaultItems) {
        self.items = items
    }

    public func key(for instance: UUID) -> String? {
        cache.withLock { cache in
            guard case .read(var keys) = load(&cache) else { return nil }
            if let key = keys[instance] { return key }
            guard cache.looked.insert(instance).inserted,
                  let data = try? items.read(instance.uuidString), let key = String(data: data, encoding: .utf8)
            else { return nil }
            keys[instance] = key
            if (try? save(keys)) != nil {
                cache.state = .read(keys)
                items.delete(instance.uuidString)
            }
            return key
        }
    }

    public func setKey(_ key: String, for instance: UUID) throws {
        try cache.withLock { cache in
            // Saving is the user's own action: ask again after a refusal.
            if case .refused = cache.state { cache.state = .unread }
            guard case .read(var keys) = load(&cache) else { throw KeychainError(status: errSecAuthFailed) }
            keys[instance] = key
            try save(keys)
            cache.state = .read(keys)
            cache.looked.insert(instance)
            items.delete(instance.uuidString)
        }
    }

    public func removeKey(for instance: UUID) {
        cache.withLock { cache in
            if case .read(var keys) = load(&cache), keys.removeValue(forKey: instance) != nil, (try? save(keys)) != nil {
                cache.state = .read(keys)
            }
            items.delete(instance.uuidString)
        }
    }

    private func load(_ cache: inout Cache) -> State {
        guard case .unread = cache.state else { return cache.state }
        do {
            let data = try items.read(Self.bundleAccount)
            let keys = try data.map { try JSONDecoder().decode([UUID: String].self, from: $0) } ?? [:]
            cache.state = .read(keys)
        } catch {
            cache.state = .refused
        }
        return cache.state
    }

    private func save(_ keys: [UUID: String]) throws {
        try items.write(JSONEncoder().encode(keys), to: Self.bundleAccount)
    }
}

public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "The Keychain refused the API key: \(message)."
    }
}

extension KeychainCredentials {
    public static var defaultItems: any SecretItems { LoginKeychainItems(service: service) }
}

/// Generic passwords of one service in the login Keychain.
public struct LoginKeychainItems: SecretItems {
    let service: String

    public func read(_ account: String) throws -> Data? {
        var query = base(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return item as? Data
    }

    public func write(_ data: Data, to account: String) throws {
        let update = [kSecValueData as String: data] as CFDictionary
        var status = SecItemUpdate(base(account) as CFDictionary, update)
        if status == errSecItemNotFound {
            status = SecItemAdd(newItem(account, data: data) as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func delete(_ account: String) {
        SecItemDelete(base(account) as CFDictionary)
    }

    /// A new item in the file-based login Keychain, which the sandbox
    /// gives each app its own access to. It sets no `kSecAttrAccessible`:
    /// that class (and its device-only variants) applies only in the
    /// data-protection Keychain, which needs a keychain access group
    /// entitlement and provisioning profile that unsigned builds and
    /// `swift test` lack. The login Keychain ignores it, so it would claim a
    /// protection the item does not have.
    func newItem(_ account: String, data: Data) -> [String: Any] {
        var item = base(account)
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "Mirmir remote API keys"
        return item
    }

    private func base(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
#endif
