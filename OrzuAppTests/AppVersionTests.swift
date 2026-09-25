import XCTest
@testable import OrzuApp

final class AppVersionTests: XCTestCase {
    func testComparesVersionsByNumbersNotText() {
        XCTAssertTrue(AppVersion.isOlder("1.0", than: "1.2"))
        XCTAssertTrue(AppVersion.isOlder("1.9", than: "1.10"), "1.10 новее 1.9, хотя строкой меньше")
        XCTAssertFalse(AppVersion.isOlder("1.10", than: "1.9"))
        XCTAssertTrue(AppVersion.isOlder("0.9.9", than: "1.0"))
    }

    func testSameOrNewerVersionIsNotOlder() {
        XCTAssertFalse(AppVersion.isOlder("1.2", than: "1.2"))
        XCTAssertFalse(AppVersion.isOlder("1.2", than: "1.2.0"), "недостающие части — нули")
        XCTAssertFalse(AppVersion.isOlder("2.0", than: "1.2"))
        XCTAssertTrue(AppVersion.isOlder("1.2", than: "1.2.1"))
    }
}
