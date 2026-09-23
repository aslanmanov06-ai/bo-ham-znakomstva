import Foundation

/// Готовая запись голосового или «кружка» во временном файле — её отправляет ChatViewModel.sendRecording.
struct MediaRecording {
    let fileURL: URL
    let kind: AttachmentKind
    let mimeType: String
    let durationSec: Int

    /// Короче секунды — случайное касание, а не сообщение.
    static let minDuration: TimeInterval = 1
    /// Совпадают с лимитами backend (attachment-rules.ts).
    static let maxVoiceDuration: TimeInterval = 30 * 60
    static let maxVideoNoteDuration: TimeInterval = 60

    static func temporaryURL(prefix: String, fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(prefix)-\(UUID().uuidString).\(fileExtension)")
    }

    /// nil — запись слишком короткая, файл удаляется.
    init?(fileURL: URL, kind: AttachmentKind, mimeType: String, duration: TimeInterval) {
        guard duration >= Self.minDuration else {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
        self.fileURL = fileURL
        self.kind = kind
        self.mimeType = mimeType
        self.durationSec = Int(duration.rounded())
    }
}

enum MediaPermissionError: LocalizedError {
    case microphone, camera

    var errorDescription: String? {
        switch self {
        case .microphone: return "Нет доступа к микрофону — разрешите его в Настройках iPhone"
        case .camera: return "Нет доступа к камере — разрешите его в Настройках iPhone"
        }
    }
}
