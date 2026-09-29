import Foundation
import Security

/// То, что нужно и приложению, и расширению уведомлений (OrzuNotificationService), чтобы расшифровать превью
/// секретного чата прямо в push: приватный ключ устройства, id вошедшего пользователя и запомненные ключи собеседников.
/// Ключ лежит в общей группе Keychain, остальное — в UserDefaults общей App Group. Файл входит в оба таргета.
enum SharedE2EStore {
    static let appGroup = "group.com.orzuapp.messenger"
    /// Тот же service, что у E2EKeyStore: account — id пользователя, данные — сырой приватный ключ Curve25519.
    static let keychainService = "com.orzuapp.messenger.e2e"

    private static let currentUserKey = "e2e.currentUserId"
    private static let pinnedKeysKey = "e2e.pinnedPeerKeys"
    private static let previousPinnedKeysKey = "e2e.previousPinnedPeerKeys"

    /// «ABCDE12345.com.orzuapp.messenger.shared». Префикс команды подставляет сборка (Info.plist → AppIdentifierPrefix);
    /// без подписи (Симулятор, CI) его нет — тогда ключ хранится как раньше, только для приложения.
    static var keychainAccessGroup: String? {
        guard
            let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
            !prefix.isEmpty, !prefix.hasPrefix("$(")
        else { return nil }
        return prefix + "com.orzuapp.messenger.shared"
    }

    /// Без App Group (сборка без подписи) — обычные UserDefaults приложения: расширения тогда всё равно нет.
    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    /// Кто вошёл на этом устройстве: расширение по нему находит свой приватный ключ. nil — никто.
    static var currentUserId: String? {
        get { defaults.string(forKey: currentUserKey) }
        set { defaults.set(newValue, forKey: currentUserKey) }
    }

    // MARK: - Запомненные ключи собеседников (trust on first use)

    static var pinnedKeys: [String: String] {
        get {
            if let keys = defaults.dictionary(forKey: pinnedKeysKey) as? [String: String] { return keys }
            // До App Group ключи лежали в UserDefaults приложения — переносим один раз.
            let legacy = UserDefaults.standard.dictionary(forKey: pinnedKeysKey) as? [String: String] ?? [:]
            if !legacy.isEmpty { defaults.set(legacy, forKey: pinnedKeysKey) }
            return legacy
        }
        set { defaults.set(newValue, forKey: pinnedKeysKey) }
    }

    /// Ключи собеседников, которым доверяли раньше: старые сообщения, зашифрованные ими, остаются читаемыми после смены ключа.
    static var previousPinnedKeys: [String: [String]] {
        get { defaults.dictionary(forKey: previousPinnedKeysKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: previousPinnedKeysKey) }
    }

    // MARK: - Приватный ключ в Keychain

    static func readPrivateKey(account: String) -> Data? {
        // Без kSecAttrAccessGroup поиск идёт по всем группам, доступным этому таргету.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Пишет в общую группу, а если её нет в подписи (errSecMissingEntitlement) — в группу приложения.
    static func writePrivateKey(_ data: Data, account: String) -> OSStatus {
        var attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if let group = keychainAccessGroup {
            attributes[kSecAttrAccessGroup as String] = group
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecMissingEntitlement else { return status }
            attributes.removeValue(forKey: kSecAttrAccessGroup as String)
        }
        return SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Ключ, созданный до общей группы, видит только приложение — переносим его, чтобы push-превью смогло расшифровать.
    static func moveToSharedGroupIfNeeded(account: String) {
        guard let group = keychainAccessGroup else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecAttrAccessGroup as String: group]
        _ = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}
