import AVKit
import SwiftUI
import UIKit

/// Фото анкеты по id вложения: скачивается с токеном, поэтому не AsyncImage.
struct DatingPhotoView: View {
    let attachmentId: String?
    var cornerRadius: CGFloat = 16

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        // Rectangle занимает ровно предложенный размер, а фото «заполняет» его поверх:
        // иначе scaledToFill раздувает раскладку родителя за пределы рамки.
        Rectangle()
            .fill(Color.secondary.opacity(0.15))
            .overlay {
                if attachmentId == nil || failed {
                    Image(systemName: "person.fill")
                        .font(.app(.largeTitle))
                        .foregroundStyle(.secondary)
                }
            }
            .shimmering(active: image == nil && attachmentId != nil && !failed)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .task(id: attachmentId) {
                failed = false
                // Прежнее фото остаётся на экране, пока грузится следующее, — листание без мигания заглушки.
                guard let attachmentId else {
                    image = nil
                    return
                }
                do {
                    let loaded = UIImage(data: try await AttachmentLoader.shared.data(for: attachmentId))
                    withAnimation(.easeOut(duration: 0.25)) { image = loaded }
                    failed = loaded == nil
                } catch {
                    image = nil
                    failed = true
                }
            }
    }

    /// Фото следующих анкет качаются заранее: карточка появляется уже с картинкой.
    static func prefetch(_ attachmentIds: [String]) {
        Task {
            for attachmentId in attachmentIds {
                // Ошибку здесь некому показать: если фото не скачалось, DatingPhotoView попробует снова и покажет заглушку.
                _ = try? await AttachmentLoader.shared.data(for: attachmentId)
            }
        }
    }
}

/// Видео анкеты: сервер отдаёт файл только с токеном, поэтому сначала кладём его во временную папку.
struct DatingVideoView: View {
    let attachmentId: String

    @State private var player: AVPlayer?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            } else if let errorMessage {
                Text(errorMessage)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task(id: attachmentId) {
            do {
                let url = try await AttachmentLoader.shared.temporaryFileURL(attachmentId: attachmentId, fileName: "video.mp4")
                player = AVPlayer(url: url)
            } catch {
                errorMessage = "Не удалось загрузить видео"
            }
        }
        .onDisappear { player?.pause() }
    }
}

/// Значок «проверен» рядом с именем.
struct VerifiedBadge: View {
    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .foregroundStyle(Color.champagne)
            .accessibilityLabel("Анкета подтверждена")
    }
}
