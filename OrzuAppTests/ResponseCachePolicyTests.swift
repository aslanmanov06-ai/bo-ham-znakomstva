import XCTest
@testable import OrzuApp

final class ResponseCachePolicyTests: XCTestCase {
    func testCachesScreensButNotSearchOrOlderPages() {
        XCTAssertTrue(APIClient.isCacheable(path: "/chats"))
        XCTAssertTrue(APIClient.isCacheable(path: "/chats/c1/messages"))
        // Настройки поиска знакомств — обычный экран, а не поисковый запрос.
        XCTAssertTrue(APIClient.isCacheable(path: "/dating/search-settings"))

        XCTAssertFalse(APIClient.isCacheable(path: "/users/search?q=%D0%B0%D0%BB%D0%B8"))
        XCTAssertFalse(APIClient.isCacheable(path: "/chats/c1/messages/search?q=hi"))
        XCTAssertFalse(APIClient.isCacheable(path: "/dating/search?username=alisa"))
        XCTAssertFalse(APIClient.isCacheable(path: "/chats/c1/messages?before=2026-09-21T10:00:00.000Z"))
        // Первая страница сетки анкет (с фильтрами) — сохраняется для офлайна, следующие — нет.
        XCTAssertTrue(APIClient.isCacheable(path: "/dating/browse?cityCode=khujand"))
        XCTAssertFalse(APIClient.isCacheable(path: "/dating/browse?cityCode=khujand&cursor=2026-06-01T00:00:00.000Z_u1"))
    }
}
