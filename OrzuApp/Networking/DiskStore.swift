import CryptoKit
import Foundation
import os

/// Папка с файлами «ключ → данные» для офлайн-режима: ответы сервера и скачанные вложения.
/// Имя файла — SHA-256 ключа, поэтому в ключе могут быть любые символы (путь с query, id).
/// Методы потокобезопасны: FileManager и атомарная запись не требуют общей блокировки.
final class DiskStore: @unchecked Sendable {
    private let directory: URL
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "DiskStore")

    /// base — .applicationSupportDirectory для того, что должно пережить нехватку места (офлайн-данные),
    /// .cachesDirectory для того, что можно скачать заново (система вправе его очистить).
    init(name: String, base: FileManager.SearchPathDirectory) {
        let root = FileManager.default.urls(for: base, in: .userDomainMask)[0]
        directory = root.appendingPathComponent(name, isDirectory: true)
    }

    func load(_ key: String) -> Data? {
        try? Data(contentsOf: fileURL(for: key))
    }

    func save(_ data: Data, for key: String) {
        do {
            try prepareDirectory()
            // Переписка и анкеты: файл читается только после первой разблокировки телефона.
            try data.write(to: fileURL(for: key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            logger.error("Не удалось сохранить на диск: \(error.localizedDescription, privacy: .public)")
        }
    }

    func remove(_ key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
    }

    /// Выход из аккаунта: данные прошлого пользователя не должны достаться следующему.
    func removeAll() {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            logger.error("Не удалось очистить \(self.directory.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Удаляет самые давние файлы, пока папка не станет меньше limitBytes.
    func trim(toBytes limitBytes: Int) {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys) else { return }
        var entries = files.compactMap { url -> (url: URL, size: Int, date: Date)? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
        var total = entries.reduce(0) { $0 + $1.size }
        guard total > limitBytes else { return }
        entries.sort { $0.date < $1.date }
        for entry in entries where total > limitBytes {
            try? FileManager.default.removeItem(at: entry.url)
            total -= entry.size
        }
    }

    private func prepareDirectory() throws {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Копия того, что и так лежит на сервере, — в iCloud-бэкап ей незачем.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }

    private func fileURL(for key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash)
    }
}
