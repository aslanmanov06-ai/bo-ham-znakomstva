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

@MainActor
final class E2EKeyHistoryTests: XCTestCase {
    private let peerId = "test-peer-\(UUID().uuidString)"

    override func tearDown() {
        SharedE2EStore.pinnedKeys.removeValue(forKey: peerId)
        SharedE2EStore.previousPinnedKeys.removeValue(forKey: peerId)
        super.tearDown()
    }

    /// После смены ключа старые сообщения собеседника остаются читаемыми, а чужой ключ — нет.
    func testReplacedKeyStaysTrusted() {
        let store = E2EKeyStore.shared
        store.pin(peerKey: "old", userId: peerId)
        store.pin(peerKey: "new", userId: peerId)

        XCTAssertTrue(store.isTrusted(peerKey: "new", userId: peerId))
        XCTAssertTrue(store.isTrusted(peerKey: "old", userId: peerId))
        XCTAssertFalse(store.isTrusted(peerKey: "forged", userId: peerId))
        XCTAssertEqual(store.status(ofPeerKey: "new", userId: peerId), .unchanged)
    }

    /// Неподтверждённый новый ключ доверенным не считается, пока его не приняли.
    func testUnacceptedKeyIsNotTrusted() {
        let store = E2EKeyStore.shared
        store.pin(peerKey: "old", userId: peerId)
        XCTAssertEqual(store.status(ofPeerKey: "new", userId: peerId), .changed)
        XCTAssertFalse(store.isTrusted(peerKey: "new", userId: peerId))
    }

    /// История ограничена, повторное подтверждение того же ключа её не раздувает.
    func testHistoryIsBoundedAndDeduplicated() {
        let store = E2EKeyStore.shared
        for index in 0..<15 { store.pin(peerKey: "key-\(index)", userId: peerId) }
        store.pin(peerKey: "key-14", userId: peerId)

        XCTAssertEqual(SharedE2EStore.previousPinnedKeys[peerId]?.count, 10)
        XCTAssertFalse(store.isTrusted(peerKey: "key-0", userId: peerId))
        XCTAssertTrue(store.isTrusted(peerKey: "key-13", userId: peerId))
    }
}
