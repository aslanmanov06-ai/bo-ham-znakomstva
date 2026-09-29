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

    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "E2E")
    private var cache: [String: Curve25519.KeyAgreement.PrivateKey] = [:]

    private init() {}

    func privateKey(for userId: String) throws -> Curve25519.KeyAgreement.PrivateKey {
        if let cached = cache[userId] { return cached }
        if let raw = SharedE2EStore.readPrivateKey(account: userId) {
            let key = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
            // Ключ мог быть создан до общей группы Keychain — тогда расширение уведомлений его не видит.
            SharedE2EStore.moveToSharedGroupIfNeeded(account: userId)
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

    /// Запомненные ключи видит и расширение уведомлений: превью расшифровывается, только если ключ совпал.
    /// Заменённый ключ уходит в историю — им зашифрованы прежние сообщения собеседника.
    func pin(peerKey key: String, userId: String) {
        var keys = pinnedKeys
        if let previous = keys[userId], previous != key {
            var history = SharedE2EStore.previousPinnedKeys
            history[userId] = Array(((history[userId] ?? []).filter { $0 != previous } + [previous]).suffix(Self.maxPreviousKeys))
            SharedE2EStore.previousPinnedKeys = history
        }
        keys[userId] = key
        SharedE2EStore.pinnedKeys = keys
    }

    /// Ключ, который пользователь подтвердил сейчас или раньше. Неподтверждённый новый ключ сюда не входит.
    func isTrusted(peerKey key: String, userId: String) -> Bool {
        pinnedKeys[userId] == key || SharedE2EStore.previousPinnedKeys[userId]?.contains(key) == true
    }

    /// Собеседник переустанавливает приложение редко — десятка прежних ключей хватает с запасом.
    private static let maxPreviousKeys = 10

    private var pinnedKeys: [String: String] {
        SharedE2EStore.pinnedKeys
    }

    private func writeKeychain(account: String, data: Data) throws {
        let status = SharedE2EStore.writePrivateKey(data, account: account)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: String(localized: "Не удалось сохранить ключ шифрования")])
        }
    }
}
