import XCTest
@testable import OrzuApp

final class MediaMessageTests: XCTestCase {
    private let openedAt = Date(timeIntervalSince1970: 1_000)
    private let photo = Attachment(id: "a1", kind: .image, mimeType: "image/jpeg", fileName: "photo.jpg", size: 10)

    private func timedPhoto(sender: String = "alice", views: [MessageView]? = nil, attachment: Attachment? = nil) -> Message {
        Message(
            id: "m1", chatId: "c1", senderId: sender, text: "", createdAt: openedAt,
            attachment: attachment ?? photo, viewTimerSec: 10, views: views
        )
    }

    func testOrdinaryMessageHasNoTimedState() {
        let message = Message(id: "m1", chatId: "c1", senderId: "alice", text: "", createdAt: openedAt, attachment: photo)
        XCTAssertNil(message.timedPhotoState(currentUserId: "bob", now: openedAt))
    }

    func testRecipientSeesUnopenedUntilOwnView() {
        // Просмотр другого участника группы не открывает фото этому пользователю.
        let message = timedPhoto(views: [MessageView(userId: "carol", openedAt: openedAt)])
        XCTAssertEqual(message.timedPhotoState(currentUserId: "bob", now: openedAt), .unopened)
    }

    func testRecipientOpenUntilTimerExpires() {
        let message = timedPhoto(views: [MessageView(userId: "bob", openedAt: openedAt)])
        let expiresAt = openedAt.addingTimeInterval(10)
        XCTAssertEqual(message.timedPhotoState(currentUserId: "bob", now: openedAt.addingTimeInterval(9)), .open(expiresAt: expiresAt))
        XCTAssertEqual(message.timedPhotoState(currentUserId: "bob", now: expiresAt), .expired)
    }

    func testSenderSeesViewedFlag() {
        XCTAssertEqual(timedPhoto().timedPhotoState(currentUserId: "alice", now: openedAt), .own(viewed: false))
        let viewed = timedPhoto(views: [MessageView(userId: "bob", openedAt: openedAt)])
        XCTAssertEqual(viewed.timedPhotoState(currentUserId: "alice", now: openedAt), .own(viewed: true))
    }

    func testPreviewTextForMedia() {
        XCTAssertEqual(timedPhoto().previewText, "Фото с таймером")
        let voice = Attachment(id: "a2", kind: .voice, mimeType: "audio/mp4", fileName: "v.m4a", size: 1, durationSec: 7)
        let note = Attachment(id: "a3", kind: .videoNote, mimeType: "video/quicktime", fileName: "n.mov", size: 1, durationSec: 7)
        XCTAssertEqual(Message(id: "1", chatId: "c", senderId: "s", text: "", createdAt: openedAt, attachment: voice).previewText, "Голосовое сообщение")
        XCTAssertEqual(Message(id: "2", chatId: "c", senderId: "s", text: "", createdAt: openedAt, attachment: note).previewText, "Видеосообщение")
    }

    func testDecodesServerMediaFields() throws {
        let json = """
        {"id":"m1","chatId":"c1","senderId":"alice","text":"","createdAt":"2026-09-19T12:00:00.000Z","viewTimerSec":15,
         "attachment":{"id":"a1","kind":"VOICE","mimeType":"audio/mp4","fileName":"v.m4a","size":100,"durationSec":42},
         "views":[{"userId":"bob","openedAt":"2026-09-19T12:00:05.000Z"}],"reactions":[]}
        """
        let message = try ISO8601Coding.makeDecoder().decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(message.attachment?.kind, .voice)
        XCTAssertEqual(message.attachment?.durationSec, 42)
        XCTAssertEqual(message.viewTimerSec, 15)
        XCTAssertEqual(message.views?.first?.userId, "bob")
    }

    func testFormattedDuration() {
        XCTAssertEqual(Attachment.formattedDuration(7), "0:07")
        XCTAssertEqual(Attachment.formattedDuration(754), "12:34")
    }

    func testTooShortRecordingIsDiscarded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("short-\(UUID().uuidString).m4a")
        try Data("x".utf8).write(to: url)

        XCTAssertNil(MediaRecording(fileURL: url, kind: .voice, mimeType: "audio/mp4", duration: 0.4))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRecordingDurationIsRounded() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ok-\(UUID().uuidString).m4a")
        try Data("x".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertEqual(MediaRecording(fileURL: url, kind: .voice, mimeType: "audio/mp4", duration: 6.6)?.durationSec, 7)
    }
}
