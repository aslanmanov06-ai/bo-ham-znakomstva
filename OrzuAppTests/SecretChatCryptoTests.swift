import CryptoKit
import XCTest
@testable import OrzuApp

final class SecretChatCryptoTests: XCTestCase {
    // Вектор посчитан независимой реализацией на Node.js (crypto: X25519 + hkdfSync + chacha20-poly1305) —
    // проверяет, что Swift-схема совпадает с задокументированной, а не только сама с собой.
    private let alicePrivate = Data(repeating: 0x11, count: 32)
    private let bobPrivate = Data(repeating: 0x22, count: 32)
    private let vectorCiphertext = "MzMzMzMzMzMzMzMzDCHY1Eh3itkbGizujDOZpyMUb2qFIaRA7u/9hh4="

    func testPublicKeysMatchNodeVector() throws {
        let alice = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: alicePrivate)
        let bob = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bobPrivate)
        XCTAssertEqual(alice.publicKey.rawRepresentation.base64EncodedString(), "e06Qm75//kTEZaIgA31gjuNYl9Me+XLwf3SJLLD3PxM=")
        XCTAssertEqual(bob.publicKey.rawRepresentation.base64EncodedString(), "D6poTtKIZ7l/Smot7l34zpdOdrcBjj8iocTPJnhXDyA=")
    }

    func testBobDecryptsNodeVector() throws {
        let alice = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: alicePrivate)
        let bob = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: bobPrivate)

        let text = try SecretChatCrypto.open(vectorCiphertext, privateKey: bob, peerPublicKey: alice.publicKey, chatId: "chat-vector", senderId: "alice-id")

        XCTAssertEqual(text, "Тест 🔐")
    }

    func testRoundTripBothDirections() throws {
        let alice = Curve25519.KeyAgreement.PrivateKey()
        let bob = Curve25519.KeyAgreement.PrivateKey()

        let sealed = try SecretChatCrypto.seal("привет", privateKey: alice, peerPublicKey: bob.publicKey, chatId: "c", senderId: "a")

        XCTAssertEqual(try SecretChatCrypto.open(sealed, privateKey: bob, peerPublicKey: alice.publicKey, chatId: "c", senderId: "a"), "привет")
        // Отправитель читает своё же сообщение тем же ключом чата.
        XCTAssertEqual(try SecretChatCrypto.open(sealed, privateKey: alice, peerPublicKey: bob.publicKey, chatId: "c", senderId: "a"), "привет")
    }

    func testRejectsWrongSenderChatOrKey() throws {
        let alice = Curve25519.KeyAgreement.PrivateKey()
        let bob = Curve25519.KeyAgreement.PrivateKey()
        let eve = Curve25519.KeyAgreement.PrivateKey()
        let sealed = try SecretChatCrypto.seal("секрет", privateKey: alice, peerPublicKey: bob.publicKey, chatId: "c", senderId: "a")

        XCTAssertThrowsError(try SecretChatCrypto.open(sealed, privateKey: bob, peerPublicKey: alice.publicKey, chatId: "c", senderId: "b"))
        XCTAssertThrowsError(try SecretChatCrypto.open(sealed, privateKey: bob, peerPublicKey: alice.publicKey, chatId: "other", senderId: "a"))
        XCTAssertThrowsError(try SecretChatCrypto.open(sealed, privateKey: eve, peerPublicKey: alice.publicKey, chatId: "c", senderId: "a"))
        XCTAssertThrowsError(try SecretChatCrypto.open("не base64", privateKey: bob, peerPublicKey: alice.publicKey, chatId: "c", senderId: "a"))
    }

    func testSafetyNumberIsSymmetricAndFormatted() {
        let first = Data(repeating: 1, count: 32)
        let second = Data(repeating: 2, count: 32)

        let number = SecretChatCrypto.safetyNumber(first, second)

        XCTAssertEqual(number, SecretChatCrypto.safetyNumber(second, first))
        XCTAssertEqual(number.split(separator: " ").count, 12)
        XCTAssertTrue(number.split(separator: " ").allSatisfy { $0.count == 5 && $0.allSatisfy(\.isNumber) })
    }
}
