import Foundation
import PythiloGit
import Security

/// Git HTTPS tokens, by host, in the Keychain and only on this device.
enum GitCredentialVault {
    private static let service = "com.sergiiziborov.Pythilo.git"

    private static func host(of address: String) -> String {
        URLComponents(string: address)?.host ?? address
    }

    static func save(address: String, username: String, token: String) throws {
        let host = host(of: address)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host,
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data("\(username)\n\(token)".utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WorkspaceFailure("Could not save the token: \(status).")
        }
    }

    static func credential(for address: String?) -> GitCredential? {
        guard let address, let saved = read(address) else { return nil }
        return GitCredential(username: saved.username, token: saved.token)
    }

    /// The saved token itself, for the GitHub API (api.github.com) only.
    static func token(for address: String) -> String? { read(address)?.token }

    private static func read(_ address: String) -> (username: String, token: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host(of: address),
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let parts = String(data: data, encoding: .utf8)?.split(separator: "\n", maxSplits: 1),
              parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    static func remove(address: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: host(of: address),
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func count() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return 0 }
        return items.count
    }
}
