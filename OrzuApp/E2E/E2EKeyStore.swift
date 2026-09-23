import CryptoKit
import Foundation
import Security
import os

/// Ключи секретных чатов этого устройства. Приватный ключ — свой у каждого аккаунта, в Keychain с
/// ThisDeviceOnly: не попадает в iCloud-бэкап и на другие устройства, поэтому секретный чат, как в Telegram,
/// привязан к устройству — после переустановки или на новом телефоне старую переписку не прочитать.
@MainActor
final class E2EKeyStore {
    enum PeerKeyStatus: Equatable {
        /// Ключ собеседника видим впервые — запоминаем (trust on first use).
        case firstSeen
        case unchanged
        /// Ключ сменился: собеседник переустановил приложение — или сервер подменил ключ. Решает пользователь.
        case changed
    }

    static let shared = E2EKeyStore()

    private let service = "com.orzuapp.messenger.e2e"
    private let pinnedKeysDefaultsKey = "e2e.pinnedPeerKeys"
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "E2E")
    private var cache: [String: Curve25519.KeyAgreement.PrivateKey] = [:]

    private init() {}

    func privateKey(for userId: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        if let cached = cache[userId] { return cached }
        if let raw = readKeychain(account: userId) {
            let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
            cache[userId] = key
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try writeKeychain(account: userId, data: key.rawRepresentation)
        cache[userId] = key
        return key
    }

    func publicKeyBase64(for userId: String) throws -> String {
        try privateKey(for: userId).publicKey.rawRepresentation.base64EncodedString()
    }

    /// Вызывается после входа: сервер должен знать актуальный публичный ключ, иначе с нами нельзя открыть секретный чат.
    func registerWithServer(userId: String) async {
        do {
            try await APIClient.shared.uploadE2EKey(publicKey: publicKeyBase64(for: userId))
        } catch {
            logger.error("Не удалось зарегистрировать E2E-ключ: \(error.localizedDescription, privacy: .public)")
        }
    }

    func status(ofPeerKey key: String, userId: String) -> PeerKeyStatus {
        guard let pinned = pinnedKeys[userId] else { return .firstSeen }
        return pinned == key ? .unchanged : .changed
    }

    func pin(peerKey key: String, userId: String) {
        var keys = pinnedKeys
        keys[userId] = key
        UserDefaults.standard.set(keys, forKey: pinnedKeysDefaultsKey)
    }

    private var pinnedKeys: [String: String] {
        UserDefaults.standard.dictionary(forKey: pinnedKeysDefaultsKey) as? [String: String] ?? [:]
    }

    private func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func writeKeychain(account: String, data: Data) throws {
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "Не удалось сохранить ключ шифрования"])
        }
    }
}
