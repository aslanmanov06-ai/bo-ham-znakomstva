import XCTest
@testable import OrzuApp

final class CurrentUserCacheTests: XCTestCase {
    private var defaults: UserDefaults!
    private var cache: CurrentUserCache!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "CurrentUserCacheTests")
        defaults.removePersistentDomain(forName: "CurrentUserCacheTests")
        cache = CurrentUserCache(defaults: defaults)
    }

    func testEmptyCacheHasNoUser() {
        XCTAssertNil(cache.load())
    }

    func testSavedUserSurvivesNewInstance() {
        let user = User(id: "u1", username: "alice", displayName: "Алиса", avatarUrl: "/users/u1/avatar?v=a1")
        cache.save(user)

        XCTAssertEqual(CurrentUserCache(defaults: defaults).load(), user)
    }

    /// Выход из аккаунта: следующий запуск не должен открыть вкладки по старому профилю.
    func testSavingNilForgetsUser() {
        cache.save(User(id: "u1", username: "alice", displayName: "Алиса", avatarUrl: nil))
        cache.save(nil)

        XCTAssertNil(cache.load())
    }

    /// Копия от старой версии приложения, которую уже не разобрать, не должна ронять запуск.
    func testUnreadableDataIsDropped() {
        defaults.set(Data("{\"id\":1}".utf8), forKey: "com.orzuapp.messenger.currentUser")

        XCTAssertNil(cache.load())
        XCTAssertNil(defaults.data(forKey: "com.orzuapp.messenger.currentUser"))
    }
}
