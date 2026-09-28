import CryptoKit
import UserNotifications

/// Правит push до показа (сервер ставит mutable-content: 1):
/// - секретный чат: сервер знает только шифротекст и шлёт «Новое сообщение» — расшифровываем текст здесь,
///   на устройстве, если ключ собеседника совпадает с тем, что приложение уже запомнило;
/// - фото: скачиваем миниатюру по подписанной ссылке и прикрепляем к уведомлению;
/// - уведомления одного чата собираются в стопку (thread-id), даже если сервер его не поставил.
/// На всё у расширения около 30 секунд; не успели — показываем то, что прислал сервер.
final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.contentHandler = contentHandler
        bestAttempt = content

        let info = content.userInfo
        if let text = Self.decryptSecretPreview(info) {
            content.body = text
        }
        if content.threadIdentifier.isEmpty, let chatId = info["chatId"] as? String, !chatId.isEmpty {
            content.threadIdentifier = chatId
        }

        guard let imageURL = Self.imageURL(info) else {
            finish(content)
            return
        }
        URLSession.shared.downloadTask(with: imageURL) { [weak self] location, response, _ in
            if let location, let attachment = Self.attachment(from: location, mimeType: response?.mimeType) {
                content.attachments = [attachment]
            }
            self?.finish(content)
        }.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        if let bestAttempt { finish(bestAttempt) }
    }

    /// Система ждёт ровно один вызов: второй (таймаут после загрузки картинки) игнорируем.
    private func finish(_ content: UNNotificationContent) {
        guard let contentHandler else { return }
        self.contentHandler = nil
        contentHandler(content)
    }

    // MARK: - Секретный чат

    /// nil — не секретный чат, нет ключей или ключ собеседника не тот, что запомнило приложение
    /// (так выглядела бы подмена ключа сервером — тогда показываем текст сервера, без расшифровки).
    static func decryptSecretPreview(_ info: [AnyHashable: Any]) -> String? {
        guard
            let ciphertext = info["ciphertext"] as? String,
            let senderKey = info["senderKey"] as? String,
            let chatId = info["chatId"] as? String,
            let senderId = info["senderId"] as? String,
            SharedE2EStore.pinnedKeys[senderId] == senderKey,
            let userId = SharedE2EStore.currentUserId,
            let raw = SharedE2EStore.readPrivateKey(account: userId),
            let privateKey = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw),
            let peerKey = try? SecretChatCrypto.publicKey(base64: senderKey)
        else { return nil }
        return try? SecretChatCrypto.open(ciphertext, privateKey: privateKey, peerPublicKey: peerKey, chatId: chatId, senderId: senderId)
    }

    // MARK: - Картинка

    /// Полный адрес или путь от сервера API («/attachments/…/thumbnail?sig=…»).
    static func imageURL(_ info: [AnyHashable: Any]) -> URL? {
        guard let value = info["imageUrl"] as? String ?? info["thumbnailUrl"] as? String, !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(string: value, relativeTo: AppConfig.apiBaseURL)?.absoluteURL
        }
        guard let url = URL(string: value), url.scheme == "https" else { return nil }
        return url
    }

    /// Вложение уведомления должно лежать в файле с правильным расширением — по нему система понимает тип.
    private static func attachment(from location: URL, mimeType: String?) -> UNNotificationAttachment? {
        let fileExtension: String
        switch mimeType {
        case "image/png": fileExtension = "png"
        case "image/gif": fileExtension = "gif"
        case "image/heic": fileExtension = "heic"
        default: fileExtension = "jpg"
        }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(fileExtension)")
        do {
            try FileManager.default.moveItem(at: location, to: target)
            return try UNNotificationAttachment(identifier: "image", url: target)
        } catch {
            return nil
        }
    }
}
