import XCTest
@testable import OrzuApp

final class ISO8601CodingTests: XCTestCase {
    func testDecodesPrismaDateWithMilliseconds() throws {
        let json = Data(#"{"id":"m1","chatId":"c1","senderId":"u1","text":"hi","createdAt":"2026-09-18T10:00:00.123Z"}"#.utf8)
        let message = try ISO8601Coding.makeDecoder().decode(Message.self, from: json)
        XCTAssertEqual(message.createdAt.timeIntervalSince1970, 1_789_725_600.123, accuracy: 0.001)
    }

    func testDecodesDateWithoutFraction() {
        XCTAssertNotNil(ISO8601Coding.date(from: "2026-09-18T10:00:00Z"))
    }

    func testRejectsGarbageDate() {
        let json = Data(#"{"id":"m1","chatId":"c1","senderId":"u1","text":"","createdAt":"вчера"}"#.utf8)
        XCTAssertThrowsError(try ISO8601Coding.makeDecoder().decode(Message.self, from: json))
    }
}
