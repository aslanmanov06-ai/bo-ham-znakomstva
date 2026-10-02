import XCTest
@testable import OrzuApp

final class MessageOutboxTests: XCTestCase {
    private func item(upload: PendingUpload? = nil, ciphertext: String? = nil) -> OutgoingMessage {
        OutgoingMessage(
            id: "4f9d6c52-3a8e-4f4b-9a57-0b1c2d3e4f50", chatId: "c1", createdAt: Date(timeIntervalSince1970: 1_790_000_000),
            text: ciphertext == nil ? "Привет" : "", ciphertext: ciphertext, senderKey: ciphertext.map { _ in "key" },
            replyToId: "m1", replyPreview: ReplyPreview(id: "m1", senderId: "u2", text: "Как дела?", attachment: nil), upload: upload
        )
    }

    /// Пузырь из очереди узнаётся в ответе сервера по clientMessageId — он обязан совпадать с id.
    func testBubbleCarriesClientMessageId() {
        let message = item().message(senderId: "u1")

        XCTAssertEqual(message.id, "4f9d6c52-3a8e-4f4b-9a57-0b1c2d3e4f50")
        XCTAssertEqual(message.clientMessageId, message.id)
        XCTAssertEqual(message.senderId, "u1")
        XCTAssertEqual(message.text, "Привет")
        XCTAssertEqual(message.replyTo?.id, "m1")
    }

    /// Секретный чат: текст на сервер не уходит, пузырь расшифровывает ChatViewModel из ciphertext.
    func testSecretBubbleKeepsCiphertext() {
        let message = item(ciphertext: "c2VhbGVk").message(senderId: "u1")

        XCTAssertEqual(message.text, "")
        XCTAssertEqual(message.ciphertext, "c2VhbGVk")
        XCTAssertEqual(message.senderKey, "key")
    }

    func testNotUploadedFileShowsPlaceholder() {
        let voice = PendingUpload(fileName: "voice.m4a", mimeType: "audio/mp4", mediaKind: .voice, durationSec: 5)
        let photo = PendingUpload(fileName: "photo.jpg", mimeType: "image/jpeg")
        let file = PendingUpload(fileName: "отчёт.pdf", mimeType: "application/pdf")

        XCTAssertEqual(item(upload: voice).message(senderId: "u1").text, "🎤 Голосовое сообщение")
        XCTAssertEqual(item(upload: photo).message(senderId: "u1").text, "📷 Фото")
        XCTAssertEqual(item(upload: file).message(senderId: "u1").text, "📎 отчёт.pdf")
    }

    /// Очередь лежит на диске в JSON и должна пережить перезапуск приложения без потерь.
    func testQueueSurvivesRestart() throws {
        let original = [item(), item(upload: PendingUpload(fileName: "photo.jpg", mimeType: "image/jpeg"))]

        let data = try ISO8601Coding.makeEncoder().encode(original)
        let restored = try ISO8601Coding.makeDecoder().decode([OutgoingMessage].self, from: data)

        XCTAssertEqual(restored, original)
    }

    /// Пауза перед повтором растёт вдвое и упирается в потолок — сервер не долбят каждые 15 секунд вечно.
    func testBackoffDoublesUpToLimit() {
        let delays = (0..<7).map { RetryBackoff.delay(attempt: $0, base: 15, maxDelay: 300) }

        XCTAssertEqual(delays, [15, 30, 60, 120, 240, 300, 300])
        XCTAssertEqual(RetryBackoff.delay(attempt: 1_000, base: 1, maxDelay: 30), 30)
    }

    /// Разброс ±20% — чтобы клиенты после сбоя сервера не возвращались к нему одновременно.
    func testBackoffJitterAndReset() {
        var backoff = RetryBackoff(base: 10, maxDelay: 100)

        let first = seconds(backoff.next())
        let second = seconds(backoff.next())
        XCTAssertEqual(first, 10, accuracy: 2.001)
        XCTAssertEqual(second, 20, accuracy: 4.001)
        XCTAssertEqual(backoff.attempt, 2)

        backoff.reset()
        XCTAssertEqual(backoff.attempt, 0)
        XCTAssertEqual(seconds(backoff.next()), 10, accuracy: 2.001)
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    /// Лимит на одно сообщение не держит всю очередь: ждёт только его чат, порядок внутри чата сохраняется.
    func testRateLimitedChatWaitsWithoutBlockingOtherChats() {
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        func message(_ id: String, chat: String, notBefore: Date? = nil) -> OutgoingMessage {
            var item = OutgoingMessage(id: id, chatId: chat, createdAt: now, text: id)
            item.notBefore = notBefore
            return item
        }
        let later = now.addingTimeInterval(3_600)
        let queue = [message("a1", chat: "a", notBefore: later), message("a2", chat: "a"), message("b1", chat: "b")]

        XCTAssertEqual(OutboxSchedule.next(in: queue, skippingChats: [], now: now), .send(queue[2]))
        XCTAssertEqual(OutboxSchedule.next(in: queue, skippingChats: ["b"], now: now), .wait(until: later))
        XCTAssertEqual(OutboxSchedule.next(in: queue, skippingChats: [], now: later), .send(queue[0]))
        XCTAssertEqual(OutboxSchedule.next(in: [], skippingChats: [], now: now), .wait(until: nil))
    }
}
