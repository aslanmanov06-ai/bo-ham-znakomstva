import Foundation
import Security

/// Хранит access/refresh токены в Keychain, а не в UserDefaults — токены не должны лежать в открытом виде на диске.
final class TokenStore {
    static let shared = TokenStore()

    private let service = "com.orzuapp.messenger.tokens"
    private let accessKey = "accessToken"
    private let refreshKey = "refreshToken"

    private init() {}

    var accessToken: String? {
        get { read(accessKey) }
        set { write(accessKey, newValue) }
    }

    var refreshToken: String? {
        get { read(refreshKey) }
        set { write(refreshKey, newValue) }
    }

    func save(tokens: AuthTokens) {
        accessToken = tokens.accessToken
        refreshToken = tokens.refreshToken
    }

    func clear() {
        accessToken = nil
        refreshToken = nil
    }

    private func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func write(_ key: String, _ value: String?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]

        SecItemDelete(query as CFDictionary)

        guard let value, let data = value.data(using: .utf8) else { return }

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
