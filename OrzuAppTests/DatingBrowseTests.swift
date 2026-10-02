import XCTest
@testable import OrzuApp

final class DatingBrowseTests: XCTestCase {
    /// Ответ живого GET /dating/browse: карточка ленты плюс liked и курсор следующей страницы.
    func testDecodesBrowsePage() throws {
        let json = Data("""
        {"cards":[{"userId":"u2","displayName":"Нигина","age":28,"gender":"FEMALE","countryCode":"TJ",
          "cityCode":"khujand","heightCm":165,"bio":"","interests":[],"education":null,"profession":null,
          "relationshipGoal":null,"maritalStatus":null,"children":null,"wantsChildren":null,"smoking":null,
          "alcohol":null,"sport":null,"cuisines":[],"hobbies":[],"photoIds":["a1"],"videoId":null,"verified":true,
          "compatibility":{"score":60,"reasons":[]},"distanceKm":null,"isNew":false,"expanded":false,"liked":true}],
         "nextCursor":"2026-06-01T00:00:00.000Z_3f2b8c1e-9a4d-4f6e-8b7a-1c2d3e4f5a6b"}
        """.utf8)

        let page = try ISO8601Coding.makeDecoder().decode(DatingBrowsePage.self, from: json)
        let item = try XCTUnwrap(page.cards.first)

        XCTAssertEqual(item.id, "u2")
        XCTAssertTrue(item.liked)
        XCTAssertEqual(item.card.profile.heightCm, 165)
        XCTAssertEqual(page.nextCursor, "2026-06-01T00:00:00.000Z_3f2b8c1e-9a4d-4f6e-8b7a-1c2d3e4f5a6b")
    }

    func testDecodesLastPage() throws {
        let page = try ISO8601Coding.makeDecoder().decode(DatingBrowsePage.self, from: Data(#"{"cards":[],"nextCursor":null}"#.utf8))
        XCTAssertTrue(page.cards.isEmpty)
        XCTAssertNil(page.nextCursor)
    }

    func testEmptyFiltersSendNothing() {
        XCTAssertTrue(DatingBrowseFilters().queryItems.isEmpty)
        XCTAssertEqual(DatingBrowseFilters().activeCount, 0)
    }

    /// Сервер ждёт списки через запятую, а незаданные фильтры не должны уходить вовсе.
    func testFiltersBecomeQueryItems() {
        var filters = DatingBrowseFilters()
        filters.cityCode = "khujand"
        filters.ageMin = 20
        filters.heightMax = 185
        filters.relationshipGoals = ["MARRIAGE", "SERIOUS"]

        let query = Dictionary(uniqueKeysWithValues: filters.queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(query, ["cityCode": "khujand", "ageMin": "20", "heightMax": "185", "relationshipGoals": "MARRIAGE,SERIOUS"])
        // Возраст и рост — по одному фильтру, как бы ни были заданы границы.
        XCTAssertEqual(filters.activeCount, 4)
    }

    @MainActor
    func testFiltersSurviveRestartAndAreForgottenOnLogout() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "DatingBrowseTests"))
        defaults.removePersistentDomain(forName: "DatingBrowseTests")
        var filters = DatingBrowseFilters()
        filters.children = "NONE"

        DatingBrowseViewModel(defaults: defaults).apply(filters)
        XCTAssertEqual(DatingBrowseViewModel(defaults: defaults).filters, filters)

        DatingBrowseViewModel.forgetFilters(defaults: defaults)
        XCTAssertEqual(DatingBrowseViewModel(defaults: defaults).filters, DatingBrowseFilters())
    }

    func testNewFiltersBecomeQueryItems() {
        var filters = DatingBrowseFilters()
        filters.gender = "MALE"
        filters.maxDistanceKm = 25
        filters.smoking = ["NEVER"]
        filters.alcohol = ["NEVER", "SOMETIMES"]

        let query = Dictionary(uniqueKeysWithValues: filters.queryItems.map { ($0.name, $0.value) })

        XCTAssertEqual(query, ["gender": "MALE", "maxDistanceKm": "25", "smoking": "NEVER", "alcohol": "NEVER,SOMETIMES"])
        XCTAssertEqual(filters.activeCount, 4)
    }

    /// Фильтры, сохранённые прошлой версией приложения (без новых полей), после обновления не сбрасываются.
    func testDecodesFiltersSavedByPreviousVersion() throws {
        let saved = Data(#"{"cityCode":"khujand","ageMin":20,"relationshipGoals":["MARRIAGE"],"maritalStatuses":[],"wantsChildren":[],"education":[],"interests":[]}"#.utf8)
        let filters = try JSONDecoder().decode(DatingBrowseFilters.self, from: saved)
        XCTAssertEqual(filters.cityCode, "khujand")
        XCTAssertEqual(filters.ageMin, 20)
        XCTAssertEqual(filters.relationshipGoals, ["MARRIAGE"])
        XCTAssertNil(filters.gender)
        XCTAssertTrue(filters.smoking.isEmpty)
    }
}
