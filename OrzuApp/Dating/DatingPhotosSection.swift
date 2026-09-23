import AVFoundation
import PhotosUI
import SwiftUI
import UIKit

/// Фото и видео анкеты сеткой из шести слотов: загрузка, порядок, удаление и статусы модерации.
/// Другим показываются только одобренные, поэтому статус каждого файла виден владельцу.
struct DatingPhotosSection: View {
    @ObservedObject var dating: DatingViewModel

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var videoItem: PhotosPickerItem?
    @State private var isUploading = false
    @State private var errorMessage: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let photoAspectRatio: CGFloat = 3 / 4
    private let maxPhotoDimension: CGFloat = 2048
    private let maxVideoDurationSec = 30

    var body: some View {
        DatingSectionCard(
            title: "Фото и видео",
            systemImage: "photo.on.rectangle.angled",
            subtitle: "Первое фото — главное. Новые фото и видео проверяет модератор: до проверки их видите только вы."
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<DatingLimits.maxPhotos, id: \.self) { slot in
                    slotView(slot)
                        .aspectRatio(photoAspectRatio, contentMode: .fit)
                }
            }
            .animation(DatingStyle.spring, value: photos)
            videoRow
        }
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            addPhotos(items)
        }
        .onChange(of: videoItem) { _, item in
            guard let item else { return }
            setVideo(item)
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var photos: [DatingPhoto] {
        dating.profile?.photos ?? []
    }

    /// Слот сетки: фото, «загружаем…», кнопка добавления (первый пустой слот) или пустое место под фото.
    @ViewBuilder
    private func slotView(_ slot: Int) -> some View {
        if photos.indices.contains(slot) {
            photoCell(photos[slot], isMain: slot == 0)
        } else if slot == photos.count {
            if isUploading {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.appElevated)
                    .shimmering()
                    .overlay { ProgressView() }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: DatingLimits.maxPhotos - photos.count,
                    matching: .images
                ) {
                    emptySlot(isAddButton: true)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Добавить фото")
            }
        } else {
            emptySlot(isAddButton: false)
        }
    }

    private func emptySlot(isAddButton: Bool) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .foregroundStyle(isAddButton ? AnyShapeStyle(DatingStyle.rose) : AnyShapeStyle(.quaternary))
            .background(Color.appElevated.opacity(isAddButton ? 0.6 : 0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if isAddButton {
                    Image(systemName: "plus")
                        .font(.app(.title2, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(DatingStyle.brandGradient, in: Circle())
                        .shadow(color: DatingStyle.rose.opacity(0.35), radius: 6, y: 3)
                }
            }
    }

    private func photoCell(_ photo: DatingPhoto, isMain: Bool) -> some View {
        DatingPhotoView(attachmentId: photo.attachmentId, cornerRadius: 14)
            .overlay(alignment: .bottomLeading) {
                if isMain {
                    badge("Аватар", systemImage: "person.crop.circle.fill", color: DatingStyle.rose)
                } else if photo.status == .pending {
                    badge("На проверке", systemImage: "clock", color: .champagne)
                } else if photo.status == .rejected {
                    badge("Отклонено", systemImage: "xmark", color: .red)
                }
            }
            .overlay(alignment: .topTrailing) {
                Menu {
                    photoActions(photo, isMain: isMain)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
                .accessibilityLabel("Действия с фото")
            }
            .contextMenu { photoActions(photo, isMain: isMain) }
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    @ViewBuilder
    private func photoActions(_ photo: DatingPhoto, isMain: Bool) -> some View {
        if !isMain {
            Button("Сделать главным", systemImage: "star") { makeMain(photo) }
        }
        Button("Удалить", systemImage: "trash", role: .destructive) { remove(photo) }
        if let reason = photo.rejectReason {
            Text(reason)
        }
    }

    @ViewBuilder
    private var videoRow: some View {
        if let video = dating.profile?.video {
            HStack(spacing: 12) {
                Image(systemName: "video.fill")
                    .foregroundStyle(DatingStyle.rose)
                    .frame(width: 36, height: 36)
                    .background(DatingStyle.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(videoStatusText(video))
                    .font(.app(.subheadline))
                Spacer()
                Button("Удалить", role: .destructive) { removeVideo() }
                    .font(.app(.subheadline))
                    .buttonStyle(.borderless)
            }
        } else {
            PhotosPicker(selection: $videoItem, matching: .videos) {
                HStack(spacing: 12) {
                    Image(systemName: "video.badge.plus")
                        .foregroundStyle(DatingStyle.rose)
                        .frame(width: 36, height: 36)
                        .background(DatingStyle.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Добавить видео о себе")
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("До \(maxVideoDurationSec) секунд — поздоровайтесь и расскажите пару слов")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .disabled(isUploading)
        }
    }

    private func videoStatusText(_ video: DatingPhoto) -> String {
        switch video.status {
        case .pending: return "Видео на проверке"
        case .approved: return "Видео опубликовано"
        case .rejected: return video.rejectReason ?? "Видео отклонено"
        }
    }

    private func badge(_ text: String, systemImage: String, color: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.app(.caption2, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
            .padding(6)
    }

    // MARK: - Действия

    private func addPhotos(_ items: [PhotosPickerItem]) {
        isUploading = true
        Task {
            defer {
                isUploading = false
                photoItems = []
            }
            var ids = photos.map(\.attachmentId)
            for item in items {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data),
                    // Фото из библиотеки часто HEIC на десятки МБ — анкете хватает JPEG 2048 px.
                    let jpeg = image.downscaled(maxDimension: maxPhotoDimension).jpegData(compressionQuality: 0.85)
                else {
                    errorMessage = "Не удалось прочитать фото"
                    continue
                }
                do {
                    let attachment = try await APIClient.shared.uploadAttachment(data: jpeg, fileName: "photo.jpg", mimeType: "image/jpeg")
                    ids.append(attachment.id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            await applyPhotos(ids)
        }
    }

    private func makeMain(_ photo: DatingPhoto) {
        var ids = photos.map(\.attachmentId)
        ids.removeAll { $0 == photo.attachmentId }
        ids.insert(photo.attachmentId, at: 0)
        Task { await applyPhotos(ids) }
    }

    private func remove(_ photo: DatingPhoto) {
        let ids = photos.map(\.attachmentId).filter { $0 != photo.attachmentId }
        guard !ids.isEmpty else {
            errorMessage = "В анкете должно остаться хотя бы одно фото"
            return
        }
        Task { await applyPhotos(ids) }
    }

    private func applyPhotos(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        do {
            dating.apply(try await APIClient.shared.setDatingPhotos(attachmentIds: ids))
            await dating.refreshVerification()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setVideo(_ item: PhotosPickerItem) {
        isUploading = true
        Task {
            defer {
                isUploading = false
                videoItem = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                errorMessage = "Не удалось прочитать видео"
                return
            }
            let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "video/mp4"
            do {
                // Длительность сервер сам не измеряет — считаем её здесь и отправляем вместе с файлом.
                let duration = try await videoDuration(data: data)
                guard duration > 0, duration <= maxVideoDurationSec else {
                    errorMessage = "Видео должно быть не длиннее \(maxVideoDurationSec) секунд"
                    return
                }
                let attachment = try await APIClient.shared.uploadAttachment(
                    data: data,
                    fileName: "profile-video.mp4",
                    mimeType: mimeType,
                    mediaKind: .video,
                    durationSec: duration
                )
                dating.apply(try await APIClient.shared.setDatingVideo(attachmentId: attachment.id))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// AVFoundation читает длительность только из файла, поэтому ролик сначала ложится во временную папку.
    private func videoDuration(data: Data) async throws -> Int {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dating-video-\(UUID().uuidString).mov")
        try data.write(to: url, options: .atomic)
        defer { try? FileManager.default.removeItem(at: url) }
        let seconds = try await AVURLAsset(url: url).load(.duration).seconds
        return Int(seconds.rounded(.up))
    }

    private func removeVideo() {
        Task {
            do {
                dating.apply(try await APIClient.shared.removeDatingVideo())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
