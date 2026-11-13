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

#if canImport(Security)
public struct KeychainError: Error, LocalizedError {
    public let status: OSStatus

    public var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "status \(status)"
        return "The Keychain refused the API key: \(message)."
    }
}

/// Generic passwords under one service, with the instance id as account.
public struct KeychainCredentials: CredentialStore {
    static let service = "tech.mirmir.app.remote-key"

    public init() {}

    public func key(for instance: UUID) -> String? {
        var query = base(instance)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func setKey(_ key: String, for instance: UUID) throws {
        let data = Data(key.utf8)
        let update = [kSecValueData as String: data] as CFDictionary
        var status = SecItemUpdate(base(instance) as CFDictionary, update)
        if status == errSecItemNotFound {
            var item = base(instance)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            item[kSecAttrLabel as String] = "Mirmir remote API key"
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func removeKey(for instance: UUID) {
        SecItemDelete(base(instance) as CFDictionary)
    }

    private func base(_ instance: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: instance.uuidString,
        ]
    }
}
#endif
