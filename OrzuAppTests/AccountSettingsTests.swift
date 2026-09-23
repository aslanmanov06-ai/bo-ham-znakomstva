import XCTest
@testable import OrzuApp

final class AccountSettingsTests: XCTestCase {
    func testDecodesServerSettings() throws {
        let json = Data("""
        {"id":"u1","username":"alice","displayName":"Алиса","avatarUrl":"/users/u1/avatar?v=a1","email":null,
         "messagePrivacy":"CONTACTS","groupInvitePrivacy":"NOBODY","hiddenFromSearch":true,"mailEnabled":false,
         "hasPassword":false,"googleLinked":true}
        """.utf8)

        let settings = try JSONDecoder().decode(AccountSettings.self, from: json)

        XCTAssertEqual(settings.messagePrivacy, .contacts)
        XCTAssertEqual(settings.groupInvitePrivacy, .nobody)
        XCTAssertEqual(settings.user.avatarUrl, "/users/u1/avatar?v=a1")
        XCTAssertFalse(settings.hasPassword)
        XCTAssertTrue(settings.googleLinked)
    }

    /// Незаполненные поля не должны уходить на сервер — иначе изменение одной настройки сбросило бы другие.
    func testPrivacyUpdateSendsOnlyChangedFields() throws {
        let data = try JSONEncoder().encode(PrivacyUpdate(hiddenFromSearch: true))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object.count, 1)
        XCTAssertEqual(object["hiddenFromSearch"] as? Bool, true)
    }
}
