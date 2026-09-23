import XCTest
@testable import OrzuApp

/// Возраст в мастере анкеты: «Вам 21 год», «Вам 23 года», «Вам 25 лет».
final class RussianPluralTests: XCTestCase {
    func testRegularForms() {
        XCTAssertEqual(RussianPlural.years(21), "21 год")
        XCTAssertEqual(RussianPlural.years(23), "23 года")
        XCTAssertEqual(RussianPlural.years(25), "25 лет")
        XCTAssertEqual(RussianPlural.years(30), "30 лет")
    }

    /// 11–14 — исключение: «11 лет», а не «11 год».
    func testTeensUseGenitivePlural() {
        XCTAssertEqual(RussianPlural.years(11), "11 лет")
        XCTAssertEqual(RussianPlural.years(14), "14 лет")
        XCTAssertEqual(RussianPlural.years(111), "111 лет")
    }

    func testBoundaries() {
        XCTAssertEqual(RussianPlural.years(0), "0 лет")
        XCTAssertEqual(RussianPlural.years(1), "1 год")
        XCTAssertEqual(RussianPlural.years(101), "101 год")
        XCTAssertEqual(RussianPlural.years(104), "104 года")
    }
}
