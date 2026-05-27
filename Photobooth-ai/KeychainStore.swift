import Foundation
import Security

/// Minimal Keychain wrapper for storing auth tokens. We use a single account
/// (`boothify.session`) holding the JSON-encoded `AuthSession`. Tokens never
/// touch UserDefaults — they live only in Keychain with `.afterFirstUnlock`
/// accessibility so the app can refresh in background after first unlock.
enum KeychainStore {
    private static let service = "com.servify.Photobooth-ai"
    private static let sessionAccount = "boothify.session"

    static func saveSession(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)
        try set(data, account: sessionAccount)
    }

    static func loadSession() -> AuthSession? {
        guard let data = get(account: sessionAccount) else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func clearSession() {
        delete(account: sessionAccount)
    }

    // MARK: - Low-level

    private static func set(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(
                domain: "KeychainStore",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Keychain write failed (\(status))"],
            )
        }
    }

    private static func get(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
