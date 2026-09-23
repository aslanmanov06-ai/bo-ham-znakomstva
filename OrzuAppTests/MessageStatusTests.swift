import XCTest
@testable import OrzuApp

final class MessageStatusTests: XCTestCase {
    private let sentAt = Date(timeIntervalSince1970: 1_000)

    private func message(reactions: [MessageReaction]? = nil) -> Message {
        Message(id: "m1", chatId: "c1", senderId: "me", text: "hi", createdAt: sentAt, reactions: reactions)
    }

    func testPendingIsSendingRegardlessOfReceipts() {
        XCTAssertEqual(message().deliveryStatus(isPending: true, deliveredAt: sentAt, readAt: sentAt), .sending)
    }

    func testWithoutReceiptsIsSent() {
        XCTAssertEqual(message().deliveryStatus(isPending: false, deliveredAt: nil, readAt: nil), .sent)
    }

    func testReceiptBeforeMessageDoesNotCount() {
        let earlier = sentAt.addingTimeInterval(-1)
        XCTAssertEqual(message().deliveryStatus(isPending: false, deliveredAt: earlier, readAt: earlier), .sent)
    }

    func testDeliveredAtExactlyCreatedAt() {
        XCTAssertEqual(message().deliveryStatus(isPending: false, deliveredAt: sentAt, readAt: nil), .delivered)
    }

    func testReadWinsOverDelivered() {
        let later = sentAt.addingTimeInterval(5)
        XCTAssertEqual(message().deliveryStatus(isPending: false, deliveredAt: later, readAt: later), .read)
    }

    func testReactionSummaryGroupsInFixedOrderAndMarksMine() {
        let reactions = [
            MessageReaction(userId: "a", emoji: "🔥"),
            MessageReaction(userId: "me", emoji: "👍"),
            MessageReaction(userId: "b", emoji: "👍"),
        ]
        let summary = message(reactions: reactions).reactionSummary(currentUserId: "me")
        XCTAssertEqual(summary, [
            ReactionSummary(emoji: "👍", count: 2, isMine: true),
            ReactionSummary(emoji: "🔥", count: 1, isMine: false),
        ])
        XCTAssertEqual(message(reactions: reactions).myReaction(currentUserId: "me"), "👍")
    }

    func testDecodesMessageWithoutNewFieldsFromOlderServer() throws {
        let json = Data(#"{"id":"m1","chatId":"c1","senderId":"u1","text":"hi","createdAt":"2026-09-18T10:00:00.123Z"}"#.utf8)
        let decoded = try ISO8601Coding.makeDecoder().decode(Message.self, from: json)
        XCTAssertNil(decoded.editedAt)
        XCTAssertEqual(decoded.reactionSummary(currentUserId: "u1"), [])
    }

    func testDecodesEditedMessageWithReactions() throws {
        let json = Data(#"{"id":"m1","chatId":"c1","senderId":"u1","text":"hi","createdAt":"2026-09-18T10:00:00.123Z","editedAt":"2026-09-18T10:05:00.000Z","reactions":[{"userId":"u2","emoji":"❤️"}]}"#.utf8)
        let decoded = try ISO8601Coding.makeDecoder().decode(Message.self, from: json)
        XCTAssertNotNil(decoded.editedAt)
        XCTAssertEqual(decoded.myReaction(currentUserId: "u2"), "❤️")
    }

    func testChatDecodesReceipts() throws {
        let json = Data(#"{"id":"c1","type":"DIRECT","title":null,"username":null,"myRole":"MEMBER","participants":[],"lastMessage":null,"deliveredAt":"2026-09-18T10:00:00.000Z","readAt":null}"#.utf8)
        let chat = try ISO8601Coding.makeDecoder().decode(Chat.self, from: json)
        XCTAssertNotNil(chat.deliveredAt)
        XCTAssertNil(chat.readAt)
    }
}
