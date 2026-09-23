import XCTest
@testable import OrzuApp

/// Общий ящик «Запросы» (GET /chat-requests): первые сообщения знакомств и обычные запросы приходят в одном списке,
/// но с разной формой отправителя — у первого сообщения это сразу анкета.
final class ChatRequestTests: XCTestCase {
    private let decoder = ISO8601Coding.makeDecoder()

    private let profileFields = """
    "userId":"u2","username":"madina","displayName":"Мадина","age":26,"gender":"FEMALE","countryCode":"TJ",
    "cityCode":"dushanbe","heightCm":null,"bio":"","interests":[],"education":null,"profession":null,
    "relationshipGoal":null,"maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,
    "alcohol":null,"sport":null,"cuisines":[],"hobbies":[],"photoIds":["p1"],"videoId":null,"verified":true
    """

    func testDecodesIntroAndRequestInOneInbox() throws {
        let json = Data("""
        {"incoming":[
          {"kind":"request","id":"r1","text":"Салом, это Далер с работы","createdAt":"2026-09-22T07:47:23.537Z",
           "from":{"userId":"u1","username":"daler","displayName":"Далер","avatarUrl":"/users/u1/avatar?v=a1","profile":null}},
          {"kind":"intro","id":"i1","text":"Привет!","createdAt":"2026-09-22T07:40:00.000Z","expiresAt":"2026-09-23T07:40:00.000Z",
           "from":{\(profileFields),"distanceKm":null}}
         ],
         "sent":[
          {"kind":"request","id":"r2","text":"Привет","createdAt":"2026-09-22T07:00:00.000Z",
           "to":{"userId":"u3","username":"farhod","displayName":"Фарход","avatarUrl":null,"profile":null}},
          {"kind":"intro","id":"i2","text":"Салом","createdAt":"2026-09-22T06:00:00.000Z","expiresAt":"2026-09-23T06:00:00.000Z",
           "to":{"userId":"u4","displayName":"Зарина","photoId":"p9"}}
         ]}
        """.utf8)

        let inbox = try decoder.decode(ChatRequestInbox.self, from: json)

        XCTAssertEqual(inbox.incoming.map(\.kind), [.request, .intro])
        XCTAssertEqual(inbox.incoming[0].from.avatarUrl, "/users/u1/avatar?v=a1")
        XCTAssertNil(inbox.incoming[0].expiresAt)
        XCTAssertEqual(inbox.incoming[1].from.username, "madina")
        XCTAssertEqual(inbox.incoming[1].from.profile?.photoIds, ["p1"])
        XCTAssertEqual(inbox.sent.map(\.recipientName), ["Фарход", "Зарина"])
        XCTAssertEqual(inbox.sent[1].photoId, "p9")
    }

    func testSendResultWithInstantMatch() throws {
        let json = Data("""
        {"kind":"intro","intro":null,"limits":{},"match":{"id":"m1","chatId":"c1","createdAt":"2026-09-22T07:00:00.000Z",
         "lastActivityAt":"2026-09-22T07:00:00.000Z","hasMessages":true,
         "partner":{"userId":"u2","displayName":"Мадина","age":26,"cityCode":"dushanbe","photoId":null}}}
        """.utf8)

        let result = try decoder.decode(SendChatRequestResult.self, from: json)

        XCTAssertEqual(result.kind, .intro)
        XCTAssertEqual(result.match?.chatId, "c1")
    }

    /// Анкета из кеша до обновления сервера — без username: разбирается, просто без @username.
    func testPublicProfileWithoutUsername() throws {
        let json = Data("{\(profileFields.replacingOccurrences(of: "\"username\":\"madina\",", with: "")),\"distanceKm\":3}".utf8)

        let profile = try decoder.decode(DatingProfilePublic.self, from: json)

        XCTAssertNil(profile.username)
    }

    /// «Написать» из анкеты: собеседник для мессенджера берётся из анкеты, без username — пустая строка, а не падение.
    func testMessengerUserFromProfile() throws {
        let profile = try decoder.decode(DatingProfilePublic.self, from: Data("{\(profileFields),\"distanceKm\":null}".utf8))

        XCTAssertEqual(profile.messengerUser.id, "u2")
        XCTAssertEqual(profile.messengerUser.username, "madina")
        XCTAssertEqual(profile.messengerUser.displayName, "Мадина")
    }
}
