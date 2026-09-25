import XCTest
@testable import OrzuApp

final class GoogleSignInResponseTests: XCTestCase {
    private func decode(_ json: String) throws -> GoogleSignInResponse {
        try JSONDecoder().decode(GoogleSignInResponse.self, from: Data(json.utf8))
    }

    func testDecodesAuthenticated() throws {
        let response = try decode("""
        {"status":"authenticated","user":{"id":"u1","username":"alice","displayName":"Алиса","avatarUrl":null,"isBot":false},
         "tokens":{"accessToken":"a","refreshToken":"r"}}
        """)

        guard case .authenticated(let auth) = response else { return XCTFail("ожидался вход") }
        XCTAssertEqual(auth.user.username, "alice")
        XCTAssertEqual(auth.tokens.refreshToken, "r")
    }

    func testDecodesRegistrationRequired() throws {
        let response = try decode("""
        {"status":"registration_required","registrationToken":"reg","profile":{"email":"ivan.petrov@gmail.com","displayName":null}}
        """)

        guard case .registrationRequired(let registration) = response else { return XCTFail("ожидалась анкета") }
        XCTAssertEqual(registration.registrationToken, "reg")
        XCTAssertNil(registration.profile.displayName)
        XCTAssertEqual(registration.suggestedUsername, "ivanpetrov")
    }

    func testUnknownStatusFails() {
        XCTAssertThrowsError(try decode(#"{"status":"something_new"}"#))
    }

    func testSuggestedUsernameSkipsUnusableAddresses() {
        func suggestion(_ email: String?) -> String {
            GoogleRegistration(registrationToken: "t", profile: .init(email: email, displayName: nil)).suggestedUsername
        }
        XCTAssertEqual(suggestion(nil), "")
        XCTAssertEqual(suggestion("а.б@gmail.com"), "", "кириллица в username не допускается")
        XCTAssertEqual(suggestion("ab@gmail.com"), "", "короче 3 символов")
        XCTAssertEqual(suggestion(String(repeating: "x", count: 40) + "@gmail.com").count, 32)
    }

    func testUsernameValidationMatchesServer() {
        XCTAssertTrue(UsernameRules.isValid("alice_1"))
        XCTAssertFalse(UsernameRules.isValid("al"))
        XCTAssertFalse(UsernameRules.isValid("alice-1"))
        XCTAssertFalse(UsernameRules.isValid("алиса"))
        XCTAssertFalse(UsernameRules.isValid(String(repeating: "x", count: 33)))
    }

    func testUsernameNormalizationDropsAtSignAndSpaces() {
        XCTAssertEqual(UsernameRules.normalized("  @alisa \n"), "alisa")
        XCTAssertEqual(UsernameRules.normalized("alisa"), "alisa")
        // Отрезается только один «@» в начале: «@@alisa» остаётся недопустимым, а не превращается в чужой username.
        XCTAssertFalse(UsernameRules.isValid(UsernameRules.normalized("@@alisa")))
    }

    func testPhoneNormalizationKeepsOnlyDigitsAfterPlus() {
        XCTAssertEqual(PhoneRules.normalized("+992 (90) 123-45-67"), "+992901234567")
        XCTAssertEqual(PhoneRules.normalized("992901234567"), "+992901234567")
    }

    func testPhoneValidationMatchesServer() {
        XCTAssertTrue(PhoneRules.isValid("+992 90 123 45 67"))
        XCTAssertTrue(PhoneRules.isValid("+123456789012345"))
        XCTAssertFalse(PhoneRules.isValid(PhoneRules.defaultPrefix), "только код страны — номера ещё нет")
        XCTAssertFalse(PhoneRules.isValid("+1234567"), "меньше 8 цифр")
        XCTAssertFalse(PhoneRules.isValid("+1234567890123456"), "больше 15 цифр")
        XCTAssertFalse(PhoneRules.isValid("+0901234567"), "код страны не начинается с 0")
    }
}
