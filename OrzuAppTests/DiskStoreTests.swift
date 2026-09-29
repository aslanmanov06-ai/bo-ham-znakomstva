import XCTest
@testable import OrzuApp

final class DiskStoreTests: XCTestCase {
    private var store: DiskStore!

    override func setUp() {
        super.setUp()
        store = DiskStore(name: "DiskStoreTests-\(UUID().uuidString)", base: .cachesDirectory)
    }

    override func tearDown() {
        store.removeAll()
        super.tearDown()
    }

    /// Очередь отправки отдаёт файл URLSession по пути: путь есть только у сохранённого и пропадает после удаления.
    func testExistingFileURLPointsAtSavedBytes() throws {
        XCTAssertNil(store.existingFileURL(for: "file-1"))

        let data = Data("video bytes".utf8)
        store.save(data, for: "file-1")
        let url = try XCTUnwrap(store.existingFileURL(for: "file-1"))
        XCTAssertEqual(try Data(contentsOf: url), data)

        store.remove("file-1")
        XCTAssertNil(store.existingFileURL(for: "file-1"))
    }

    /// Запись из временного файла попадает в очередь копией: исходник можно удалить, повторная копия заменяет прежнюю.
    func testCopyFileSurvivesSourceRemovalAndReplaces() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("first".utf8).write(to: source)
        try store.copyFile(at: source, for: "file-1")
        try FileManager.default.removeItem(at: source)
        XCTAssertEqual(store.load("file-1"), Data("first".utf8))

        try Data("second".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        try store.copyFile(at: source, for: "file-1")
        XCTAssertEqual(store.load("file-1"), Data("second".utf8))
    }

    /// Исходника нет — ошибка, а не пустой файл в очереди.
    func testCopyMissingFileThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try store.copyFile(at: missing, for: "file-1"))
        XCTAssertNil(store.existingFileURL(for: "file-1"))
    }

    /// Ключ — путь запроса с query: символы «/», «?», «=» не должны ломать имя файла.
    func testSavesAndLoadsByRequestPath() {
        let data = Data("[{\"id\":\"c1\"}]".utf8)
        store.save(data, for: "/chats/c1/messages?before=2026-09-21T10:00:00.000Z")

        XCTAssertEqual(store.load("/chats/c1/messages?before=2026-09-21T10:00:00.000Z"), data)
        XCTAssertNil(store.load("/chats/c1/messages"))
    }

    func testRemoveAllForgetsEverything() {
        store.save(Data("a".utf8), for: "/chats")
        store.save(Data("b".utf8), for: "/auth/me")

        store.removeAll()

        XCTAssertNil(store.load("/chats"))
        XCTAssertNil(store.load("/auth/me"))
    }

    func testTrimDropsOldestFirst() {
        store.save(Data(count: 600), for: "old")
        // Даты изменения у файлов, записанных подряд, могут совпасть — разносим явно.
        Thread.sleep(forTimeInterval: 0.05)
        store.save(Data(count: 600), for: "new")

        store.trim(toBytes: 1_000)

        XCTAssertNil(store.load("old"))
        XCTAssertEqual(store.load("new")?.count, 600)
    }

    func testTrimKeepsStoreWithinLimit() {
        store.save(Data(count: 100), for: "a")

        store.trim(toBytes: 1_000)

        XCTAssertEqual(store.load("a")?.count, 100)
    }
}
