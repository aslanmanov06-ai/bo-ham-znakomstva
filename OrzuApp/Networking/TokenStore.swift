import Foundation
import Security
import os

/// Хранит access/refresh токены в Keychain, а не в UserDefaults — токены не должны лежать в открытом виде на диске.
final class TokenStore {
    static let shared = TokenStore()

    private let service = "com.orzuapp.messenger.tokens"
    private let accessKey = "accessToken"
    private let refreshKey = "refreshToken"
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "TokenStore")

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

        guard let value, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecSuccess && status != errSecItemNotFound {
                logger.error("Не удалось удалить \(key, privacy: .public) из Keychain: \(status, privacy: .public)")
            }
            return
        }

        // ThisDeviceOnly: токены не переезжают с бэкапом на другой телефон — там нужно войти заново.
        // Обновляем запись на месте, а не «удалить и добавить»: при сбое добавления старый токен не пропадёт.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item.merge(attributes) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        }
        if status != errSecSuccess {
            logger.error("Не удалось сохранить \(key, privacy: .public) в Keychain: \(status, privacy: .public)")
        }
    }
}
