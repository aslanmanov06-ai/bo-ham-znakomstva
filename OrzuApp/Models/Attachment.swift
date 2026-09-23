import Foundation

enum AttachmentKind: String, Codable, Hashable {
    case image = "IMAGE"
    case file = "FILE"
    case voice = "VOICE"
    /// Видеосообщение-«кружок».
    case videoNote = "VIDEO_NOTE"
    /// Короткий ролик о себе для анкеты знакомств — в чат не отправляется.
    case video = "VIDEO"
}

struct Attachment: Codable, Identifiable, Hashable {
    let id: String
    let kind: AttachmentKind
    let mimeType: String
    let fileName: String
    let size: Int
    /// Только у голосовых и видеосообщений.
    var durationSec: Int? = nil

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    /// «0:07», «12:34» — как в «Диктофоне».
    static func formattedDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
