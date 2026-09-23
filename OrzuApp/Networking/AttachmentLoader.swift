import Foundation

/// Кеш скачанных вложений: при прокрутке чата картинки не качаются заново,
/// а параллельные запросы одного и того же вложения схлопываются в один.
/// Копия на диске показывает фото, голосовые и аватары без сети. Фото с таймером сюда не попадают —
/// их TimedPhotoViewer качает напрямую, мимо кеша.
actor AttachmentLoader {
    static let shared = AttachmentLoader()

    /// Хватает на сотни фото и голосовых и не раздувает место, которое приложение занимает на телефоне.
    private static let diskLimitBytes = 300 * 1024 * 1024

    private let cache: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private let disk = DiskStore(name: "Attachments", base: .cachesDirectory)
    private var inFlight: [String: Task<Data, Error>] = [:]

    private init() {
        let disk = disk
        Task.detached(priority: .utility) { disk.trim(toBytes: Self.diskLimitBytes) }
    }

    func data(for attachmentId: String) async throws -> Data {
        try await cached(key: attachmentId) { try await APIClient.shared.downloadAttachment(id: attachmentId) }
    }

    /// Путь аватара содержит ?v=<версия>, поэтому новый аватар — новый ключ кеша, старый не показывается.
    func avatar(path: String) async throws -> Data {
        try await cached(key: path) { try await APIClient.shared.downloadAvatar(path: path) }
    }

    private func cached(key: String, load: @escaping @Sendable () async throws -> Data) async throws -> Data {
        if let cached = cache.object(forKey: key as NSString) {
            return cached as Data
        }
        if let stored = disk.load(key) {
            cache.setObject(stored as NSData, forKey: key as NSString, cost: stored.count)
            return stored
        }
        if let task = inFlight[key] {
            return try await task.value
        }

        let task = Task { try await load() }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let data = try await task.value
        cache.setObject(data as NSData, forKey: key as NSString, cost: data.count)
        disk.save(data, for: key)
        return data
    }

    /// Выход из аккаунта: чужие фото и аватары не должны остаться следующему пользователю.
    func removeAll() {
        cache.removeAllObjects()
        disk.removeAll()
    }

    /// QuickLook умеет показывать только файлы на диске — кладём вложение во временную папку под исходным именем.
    func temporaryFileURL(for attachment: Attachment) async throws -> URL {
        try await temporaryFileURL(attachmentId: attachment.id, fileName: attachment.fileName)
    }

    /// У видео анкеты клиент знает только id вложения, а AVPlayer играет лишь файл с диска.
    func temporaryFileURL(attachmentId: String, fileName: String) async throws -> URL {
        let data = try await data(for: attachmentId)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(attachmentId, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(fileName.replacingOccurrences(of: "/", with: "_"))
        try data.write(to: url, options: .atomic)
        return url
    }
}
