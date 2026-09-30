import Foundation
import Security

/// Somewhere to keep API keys. The app uses the Keychain; tests and snapshots use memory.
public protocol SecretStore: AnyObject {
    func read(_ account: String) -> String?
    func contains(_ account: String) -> Bool
    func save(_ secret: String, account: String) throws
    func delete(_ account: String) throws
}

public struct KeychainError: Error, LocalizedError, Equatable {
    public var status: OSStatus

    public var errorDescription: String? {
        let text = SecCopyErrorMessageString(status, nil) as String?
        return "Keychain error \(status)" + (text.map { ": \($0)" } ?? "")
    }
}

/// API keys as generic passwords in the login keychain: service `dev.islet.Islet.ai`, one
/// account per provider, readable only while the Mac is unlocked. The default access list
/// trusts only the app that created the item. Keys never go to config.json, logs or child
/// processes.
public final class KeychainStore: SecretStore {
    public static let defaultService = "dev.islet.Islet.ai"
    public let service: String

    public init(service: String = KeychainStore.defaultService) {
        self.service = service
    }

    /// The query that identifies one item.
    public func query(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func read(_ account: String) -> String? {
        var q = query(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Whether a key is stored, without reading it.
    public func contains(_ account: String) -> Bool {
        var q = query(account: account)
        q[kSecReturnAttributes as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess
    }

    public func save(_ secret: String, account: String) throws {
        let data = Data(secret.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemUpdate(query(account: account) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = query(account: account)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        add[kSecAttrLabel as String] = "Islet (\(account) API key)"
        let added = SecItemAdd(add as CFDictionary, nil)
        guard added == errSecSuccess else { throw KeychainError(status: added) }
    }

    public func delete(_ account: String) throws {
        let status = SecItemDelete(query(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

/// Keys held in memory only (tests, snapshots).
public final class MemorySecretStore: SecretStore {
    private var items: [String: String]
    private let lock = NSLock()

    public init(_ items: [String: String] = [:]) {
        self.items = items
    }

    public func read(_ account: String) -> String? { lock.withLock { items[account] } }
    public func contains(_ account: String) -> Bool { read(account) != nil }
    public func save(_ secret: String, account: String) throws { lock.withLock { items[account] = secret } }
    public func delete(_ account: String) throws { _ = lock.withLock { items.removeValue(forKey: account) } }
}
