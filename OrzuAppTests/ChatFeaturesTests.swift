import XCTest
@testable import OrzuApp

/// Разбор ответов backend для ответов, пересылки, присутствия и закрепления — формы взяты из
/// messagePublicInclude, ChatsService.listForUser и presenceOf.
final class ChatFeaturesTests: XCTestCase {
    private let decoder = ISO8601Coding.makeDecoder()

    func testReplyAndForwardDecode() throws {
        let json = """
        {"id":"m2","chatId":"c1","senderId":"u2","text":"Да","createdAt":"2026-09-20T10:00:00.000Z",
         "attachmentId":null,"ciphertext":null,"senderKey":null,"editedAt":null,"viewTimerSec":null,
         "replyToId":"m1","forwardedFromId":"u9","forwardedFromName":"Бахром",
         "attachment":null,"reactions":[],"views":[],
         "replyTo":{"id":"m1","senderId":"u1","text":"","ciphertext":null,"senderKey":null,"attachment":{"kind":"IMAGE"}}}
        """
        let message = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertEqual(message.replyTo?.id, "m1")
        XCTAssertEqual(message.replyTo?.previewText, "Фото")
        XCTAssertEqual(message.forwardedFromId, "u9")
        XCTAssertEqual(message.forwardedFromName, "Бахром")
    }

    /// Оригинал удалили — сервер отдаёт replyTo: null, а у обычного сообщения нет и пометки о пересылке.
    func testPlainMessageHasNoReplyOrForward() throws {
        let json = """
        {"id":"m3","chatId":"c1","senderId":"u2","text":"Привет","createdAt":"2026-09-20T10:00:00Z",
         "replyTo":null,"forwardedFromId":null,"forwardedFromName":null}
        """
        let message = try decoder.decode(Message.self, from: Data(json.utf8))
        XCTAssertNil(message.replyTo)
        XCTAssertNil(message.forwardedFromName)
    }

    func testEncryptedReplyPreviewDoesNotLeakCiphertext() {
        let reply = ReplyPreview(id: "m1", senderId: "u1", text: "", ciphertext: "AAAA")
        XCTAssertEqual(reply.previewText, "🔒 Зашифрованное сообщение")
    }

    /// Чат удалённой пары: только для чтения — писать и звонить нельзя, в списке он во вкладке «Удалённые».
    func testClosedChatOfDeletedPairIsReadOnly() throws {
        let json = """
        {"id":"c1","type":"DIRECT","title":null,"username":null,"myRole":"MEMBER",
         "participants":[{"id":"u2","username":"madina","displayName":"Мадина","avatarUrl":null,"isBot":false}],
         "lastMessage":null,"deliveredAt":null,"readAt":null,
         "closedAt":"2026-09-25T10:00:00.000Z","deletesAt":"2026-10-25T10:00:00.000Z"}
        """
        let chat = try decoder.decode(Chat.self, from: Data(json.utf8))

        XCTAssertTrue(chat.isClosed)
        XCTAssertFalse(chat.canPost)
        XCTAssertFalse(chat.canCall)
        XCTAssertTrue(chat.canDelete, "убрать у себя можно")
    }

    func testChatListItemWithPinAndPresence() throws {
        let json = """
        {"id":"c1","type":"DIRECT","title":null,"username":null,"myRole":"MEMBER",
         "pinnedAt":"2026-09-20T09:00:00.000Z",
         "participants":[{"id":"u2","username":"aziz","displayName":"Азиз","avatarUrl":null,"isBot":false,
           "presence":{"online":false,"lastSeenAt":null,"lastSeen":"WITHIN_WEEK"}}],
         "lastMessage":null,"deliveredAt":null,"readAt":null}
        """
        let chat = try decoder.decode(Chat.self, from: Data(json.utf8))
        XCTAssertNotNil(chat.pinnedAt)
        XCTAssertEqual(chat.peer?.presence?.lastSeen, .withinWeek)
        XCTAssertEqual(chat.peer?.presence?.subtitle(), "был(а) на этой неделе")
        XCTAssertTrue(chat.canDelete)
    }

    /// В группе собеседника нет: ни «в сети», ни удаления чата (из группы выходят).
    func testGroupHasNoPeer() {
        let group = Chat(id: "g", type: .group, title: "Семья", username: nil, myRole: .member,
                         participants: [User(id: "u2", username: "a", displayName: "A", avatarUrl: nil)], lastMessage: nil)
        XCTAssertNil(group.peer)
        XCTAssertFalse(group.canDelete)
    }

    func testPresenceSubtitle() {
        XCTAssertEqual(Presence(online: true, lastSeen: .online).subtitle(), "в сети")
        // Скрытое время: сервер отдаёт online=false и приблизительную давность.
        XCTAssertEqual(Presence(online: false, lastSeen: .recently).subtitle(), "был(а) недавно")
        XCTAssertEqual(Presence(online: false, lastSeen: .longAgo).subtitle(), "был(а) давно")
    }

    func testListOrderKeepsPinnedOnTop() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        func chat(_ id: String, pinnedAt: Date? = nil, lastAt: Date?) -> Chat {
            let last = lastAt.map { Message(id: "m\(id)", chatId: id, senderId: "u", text: "t", createdAt: $0) }
            return Chat(id: id, type: .direct, title: id, username: nil, myRole: .member, pinnedAt: pinnedAt, participants: [], lastMessage: last)
        }
        let chats = [
            chat("fresh", lastAt: base.addingTimeInterval(500)),
            chat("pinnedEarly", pinnedAt: base, lastAt: nil),
            chat("empty", lastAt: nil),
            chat("pinnedLate", pinnedAt: base.addingTimeInterval(10), lastAt: base),
            chat("old", lastAt: base.addingTimeInterval(100)),
        ]
        XCTAssertEqual(chats.sortedForList().map(\.id), ["pinnedLate", "pinnedEarly", "fresh", "old", "empty"])
    }

    // MARK: - Ссылки на людей и каналы

    func testParsesUniversalAndSchemeLinks() {
        XCTAssertEqual(DeepLink.parse(URL(string: "https://adm.orzu.pro/u/Alisa")!), .user(username: "alisa"))
        XCTAssertEqual(DeepLink.parse(URL(string: "https://adm.orzu.pro/c/news_tj")!), .channel(username: "news_tj"))
        XCTAssertEqual(DeepLink.parse(URL(string: "boham://u/alisa")!), .user(username: "alisa"))
        XCTAssertEqual(DeepLink.parse(URL(string: "boham://c/news_tj/")!), .channel(username: "news_tj"))
    }

    func testRejectsForeignAndMalformedLinks() {
        XCTAssertNil(DeepLink.parse(URL(string: "https://evil.example/u/alisa")!))
        XCTAssertNil(DeepLink.parse(URL(string: "https://adm.orzu.pro/u/")!))
        XCTAssertNil(DeepLink.parse(URL(string: "https://adm.orzu.pro/x/alisa")!))
        XCTAssertNil(DeepLink.parse(URL(string: "https://adm.orzu.pro/u/a")!))
        XCTAssertNil(DeepLink.parse(URL(string: "boham://u/alisa/extra")!))
        // Обратный адрес Google Sign-In ссылкой не считается — его разбирает GIDSignIn.
        XCTAssertNil(DeepLink.parse(URL(string: "com.googleusercontent.apps.123:/oauth2redirect")!))
    }

    func testShareLinkRoundTrips() {
        let link = DeepLink.user(username: "alisa")
        XCTAssertEqual(link.url.absoluteString, "https://adm.orzu.pro/u/alisa")
        XCTAssertEqual(DeepLink.parse(link.url), link)
    }
}

final class SyncPageTests: XCTestCase {
    func testParsesEventsAndCursor() throws {
        let json = #"{"events":[{"type":"message.deleted","chatId":"c1","messageId":"m1","seq":41}],"lastSeq":41,"hasMore":true,"resetRequired":false}"#
        let page = try XCTUnwrap(SyncPage(data: Data(json.utf8)))
        XCTAssertEqual(page.events.count, 1)
        XCTAssertEqual(page.events.first?["seq"] as? Int, 41)
        XCTAssertEqual(page.lastSeq, 41)
        XCTAssertTrue(page.hasMore)
        XCTAssertFalse(page.resetRequired)
    }

    /// Журнал стёрт: событий нет, клиент перечитывает экраны и продолжает с lastSeq.
    func testResetRequiredWithoutEvents() throws {
        let page = try XCTUnwrap(SyncPage(data: Data(#"{"events":[],"lastSeq":900,"hasMore":false,"resetRequired":true}"#.utf8)))
        XCTAssertTrue(page.resetRequired)
        XCTAssertEqual(page.lastSeq, 900)
    }

    func testRejectsMalformedBody() {
        XCTAssertNil(SyncPage(data: Data(#"{"events":"nope","lastSeq":1}"#.utf8)))
        XCTAssertNil(SyncPage(data: Data("not json".utf8)))
    }
}

final class SyncCursorTests: XCTestCase {
    /// Первое подключение в запуске ничего не докачивает, а переподключение — с последнего увиденного seq.
    func testCatchesUpFromLastSeenSeq() {
        var cursor = SyncCursor()
        XCTAssertNil(cursor.ready(seq: 100))
        cursor.seen(seq: 105)
        XCTAssertEqual(cursor.ready(seq: 120), 105)
        XCTAssertTrue(cursor.isCatchingUp)

        cursor.seen(seq: 110) // из журнала
        cursor.seen(seq: 121) // живое, уже после ready
        XCTAssertEqual(cursor.lastSeq, 105)
        cursor.finishCatchUp(through: 120)
        XCTAssertEqual(cursor.lastSeq, 121)
        XCTAssertFalse(cursor.isCatchingUp)
    }

    /// Сорвавшаяся докачка не сдвигает курсор: промежуток запросится при следующем переподключении.
    func testFailedCatchUpKeepsGap() {
        var cursor = SyncCursor()
        _ = cursor.ready(seq: 10)
        XCTAssertEqual(cursor.ready(seq: 50), 10)
        cursor.seen(seq: 51)
        cursor.abandonCatchUp()
        XCTAssertEqual(cursor.lastSeq, 10)
        XCTAssertEqual(cursor.ready(seq: 60), 10)
    }

    /// Пока сокета не было, событий не случилось — докачивать нечего.
    func testNothingMissed() {
        var cursor = SyncCursor()
        _ = cursor.ready(seq: 7)
        XCTAssertNil(cursor.ready(seq: 7))
        XCTAssertFalse(cursor.isCatchingUp)
    }
}
