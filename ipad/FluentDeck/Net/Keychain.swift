import Foundation
import Security

/// Device tokens, one per paired PC (keyed by the host's id).
///
/// If the Keychain refuses a write (an unsigned Simulator build has no Keychain access), the
/// token is still kept in memory for this launch, so pairing and authenticated assets work.
enum Keychain {
    private static let service = "FluentDeck.hostToken"
    nonisolated(unsafe) private static var memory: [String: String] = [:]

    static func token(for hostId: String) -> String? {
        storedToken(for: hostId) ?? memory[hostId]
    }

    private static func storedToken(for hostId: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String, for hostId: String) {
        deleteToken(for: hostId)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId,
            kSecValueData as String: Data(token.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        memory[hostId] = token
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func deleteToken(for hostId: String) {
        memory[hostId] = nil
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
