import Combine
import Foundation

/// Сколько уже ушло у фоновых загрузок вложений — для кольца прогресса на пузыре отправляемого фото.
/// Ключ — id загрузки (PendingUpload.uploadId); после окончания запись убирается.
@MainActor
final class UploadProgressCenter: ObservableObject {
    static let shared = UploadProgressCenter()

    struct Progress: Equatable {
        let sent: Int64
        let total: Int64

        var fraction: Double { total > 0 ? min(Double(sent) / Double(total), 1) : 0 }
    }

    @Published private(set) var progress: [String: Progress] = [:]

    func update(uploadId: String, sent: Int64, total: Int64) {
        progress[uploadId] = Progress(sent: sent, total: total)
    }

    func finish(uploadId: String) {
        progress.removeValue(forKey: uploadId)
    }
}
