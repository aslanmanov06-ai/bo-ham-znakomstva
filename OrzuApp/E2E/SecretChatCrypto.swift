import CryptoKit
import Foundation

/// Шифрование секретных чатов. Схема (совпадает с проверкой в backend smoke-тесте):
/// ключ чата = HKDF-SHA256(X25519(мой приватный, публичный собеседника), salt "orzu-e2e-v1", info = chatId),
/// сообщение = ChaChaPoly(текст), AAD = "chatId:senderId" — сервер не может ни прочитать текст, ни выдать
/// сообщение одного участника за сообщение другого или перенести его в другой чат.
///
/// Ключи статические (без double ratchet): утечка приватного ключа устройства раскрывает всю переписку
/// этого чата — это осознанный компромисс MVP, см. README.
enum SecretChatCrypto {
    enum CryptoError: LocalizedError {
        case invalidKey
        case invalidCiphertext

        var errorDescription: String? {
            switch self {
            case .invalidKey: return "Некорректный ключ шифрования"
            case .invalidCiphertext: return "Не удалось расшифровать сообщение"
            }
        }
    }

    private static let salt = Data("orzu-e2e-v1".utf8)

    static func seal(
        _ text: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        chatId: String,
        senderId: String
    ) throws -> String {
        let key = try chatKey(privateKey: privateKey, peerPublicKey: peerPublicKey, chatId: chatId)
        let box = try ChaChaPoly.seal(Data(text.utf8), using: key, authenticating: aad(chatId: chatId, senderId: senderId))
        return box.combined.base64EncodedString()
    }

    static func open(
        _ ciphertext: String,
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        chatId: String,
        senderId: String
    ) throws -> String {
        guard let combined = Data(base64Encoded: ciphertext) else { throw CryptoError.invalidCiphertext }
        let key = try chatKey(privateKey: privateKey, peerPublicKey: peerPublicKey, chatId: chatId)
        do {
            let box = try ChaChaPoly.SealedBox(combined: combined)
            let plaintext = try ChaChaPoly.open(box, using: key, authenticating: aad(chatId: chatId, senderId: senderId))
            guard let text = String(data: plaintext, encoding: .utf8) else { throw CryptoError.invalidCiphertext }
            return text
        } catch {
            throw CryptoError.invalidCiphertext
        }
    }

    static func publicKey(base64: String) throws -> Curve25519.KeyAgreement.PublicKey {
        guard let raw = Data(base64Encoded: base64) else { throw CryptoError.invalidKey }
        do {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
        } catch {
            throw CryptoError.invalidKey
        }
    }

    /// Код безопасности для сверки «глаза в глаза»: одинаков у обоих участников, потому что ключи сортируются.
    /// 60 цифр группами по 5, как в Signal, — сверять их вслух проще, чем hex.
    static func safetyNumber(_ firstKey: Data, _ secondKey: Data) -> String {
        let ordered = [firstKey, secondKey].sorted { $0.lexicographicallyPrecedes($1) }
        let digest = SHA512.hash(data: ordered[0] + ordered[1])
        let digits = digest.prefix(30).map { String(format: "%02d", Int($0) % 100) }.joined()
        return stride(from: 0, to: digits.count, by: 5).map { offset in
            let start = digits.index(digits.startIndex, offsetBy: offset)
            return String(digits[start..<digits.index(start, offsetBy: 5)])
        }.joined(separator: " ")
    }

    private static func chatKey(
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        peerPublicKey: Curve25519.KeyAgreement.PublicKey,
        chatId: String
    ) throws -> SymmetricKey {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: peerPublicKey)
        return shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data(chatId.utf8), outputByteCount: 32)
    }

    private static func aad(chatId: String, senderId: String) -> Data {
        Data("\(chatId):\(senderId)".utf8)
    }
}
