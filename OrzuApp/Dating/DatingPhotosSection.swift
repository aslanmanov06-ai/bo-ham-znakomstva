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
    @StateObject private var voiceRecorder = VoiceRecorder()

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
    private let photoAspectRatio: CGFloat = 3 / 4
    private let maxPhotoDimension: CGFloat = 2048
    private let maxVideoDurationSec = 30

    var body: some View {
        DatingSectionCard(
            title: String(localized: "Фото и видео"),
            systemImage: "photo.on.rectangle.angled",
            subtitle: String(localized: "Первое фото — главное. Новые фото и видео проверяет модератор: до проверки их видите только вы.")
        ) {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(0..<DatingLimits.maxPhotos, id: \.self) { slot in
                    slotView(slot)
                        .aspectRatio(photoAspectRatio, contentMode: .fit)
                }
            }
            .animation(DatingStyle.spring, value: photos)
            videoRow
            voiceRow
        }
        .onChange(of: voiceRecorder.elapsed) { _, elapsed in
            // Упёрлись в лимит — сохраняем то, что успели сказать.
            if elapsed >= TimeInterval(DatingLimits.maxVoiceIntroSec) { finishVoice() }
        }
        .onDisappear { voiceRecorder.cancel() }
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
                    badge(String(localized: "Аватар"), systemImage: "person.crop.circle.fill", color: DatingStyle.rose)
                } else if photo.status == .pending {
                    badge(String(localized: "На проверке"), systemImage: "clock", color: .champagne)
                } else if photo.status == .rejected {
                    badge(String(localized: "Отклонено"), systemImage: "xmark", color: .red)
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

    /// Строка появляется, только если сервер умеет голосовое приветствие (прислал ключ voice).
    @ViewBuilder
    private var voiceRow: some View {
        if let profile = dating.profile, profile.supportsVoice {
            if let voice = profile.voice {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        rowIcon("waveform")
                        Text(voiceStatusText(voice))
                            .font(.app(.subheadline))
                        Spacer()
                        Button("Удалить", role: .destructive) { removeVoice() }
                            .font(.app(.subheadline))
                            .buttonStyle(.borderless)
                    }
                    VoiceMessageView(
                        attachment: Attachment(
                            id: voice.attachmentId, kind: .voice, mimeType: "audio/mp4", fileName: "voice.m4a", size: 0,
                            durationSec: profile.shared.voiceDurationSec
                        ),
                        isMine: false
                    ) { errorMessage = $0 }
                }
            } else if voiceRecorder.isRecording {
                HStack(spacing: 12) {
                    rowIcon("mic.fill", tint: .red)
                    Text("Запись · \(Attachment.formattedDuration(Int(voiceRecorder.elapsed))) из \(Attachment.formattedDuration(DatingLimits.maxVoiceIntroSec))")
                        .font(.app(.subheadline).monospacedDigit())
                    Spacer()
                    Button("Отмена") { voiceRecorder.cancel() }
                        .font(.app(.subheadline))
                        .buttonStyle(.borderless)
                    Button("Готово") { finishVoice() }
                        .font(.app(.subheadline, weight: .semibold))
                        .buttonStyle(.borderless)
                }
            } else {
                Button(action: startVoice) {
                    HStack(spacing: 12) {
                        rowIcon("mic.badge.plus")
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Добавить голосовое приветствие")
                                .font(.app(.subheadline, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("До \(DatingLimits.maxVoiceIntroSec) секунд — скажите пару слов своим голосом")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .disabled(isUploading)
            }
        }
    }

    private func rowIcon(_ systemImage: String, tint: Color = DatingStyle.rose) -> some View {
        Image(systemName: systemImage)
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func voiceStatusText(_ voice: DatingPhoto) -> String {
        if voice.isProcessing { return String(localized: "Голосовое обрабатывается…") }
        if voice.processingFailed { return String(localized: "Не удалось обработать голосовое — запишите заново") }
        switch voice.status {
        case .pending: return String(localized: "Голосовое на проверке")
        case .approved: return String(localized: "Голосовое опубликовано")
        case .rejected: return voice.rejectReason ?? String(localized: "Голосовое отклонено")
        }
    }

    private func videoStatusText(_ video: DatingPhoto) -> String {
        if video.isProcessing { return String(localized: "Видео обрабатывается…") }
        if video.processingFailed { return String(localized: "Не удалось обработать видео — загрузите другое") }
        switch video.status {
        case .pending: return String(localized: "Видео на проверке")
        case .approved: return String(localized: "Видео опубликовано")
        case .rejected: return video.rejectReason ?? String(localized: "Видео отклонено")
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
                    errorMessage = String(localized: "Не удалось прочитать фото")
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
            errorMessage = String(localized: "В анкете должно остаться хотя бы одно фото")
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
                errorMessage = String(localized: "Не удалось прочитать видео")
                return
            }
            do {
                // Слишком длинный ролик отклоняется ещё до загрузки; точную длительность сервер измерит сам.
                let videoURL = try await ProfileVideoExporter.export(data, maxDurationSec: maxVideoDurationSec)
                defer { try? FileManager.default.removeItem(at: videoURL) }
                // Ролик до 90 МБ — по ссылке с диска, без второй копии в памяти.
                let attachment = try await APIClient.shared.uploadFile(
                    at: videoURL, fileName: "profile-video.mp4", mimeType: "video/mp4", mediaKind: .video
                )
                dating.apply(try await APIClient.shared.setDatingVideo(attachmentId: attachment.id))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startVoice() {
        Task {
            do {
                VoicePlayer.shared.stop()
                try await voiceRecorder.start()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func finishVoice() {
        guard let recording = voiceRecorder.finish() else { return }
        isUploading = true
        Task {
            defer {
                isUploading = false
                try? FileManager.default.removeItem(at: recording.fileURL)
            }
            do {
                let data = try Data(contentsOf: recording.fileURL)
                let attachment = try await APIClient.shared.uploadAttachment(
                    data: data,
                    fileName: recording.fileURL.lastPathComponent,
                    mimeType: recording.mimeType,
                    mediaKind: .voice,
                    durationSec: min(recording.durationSec, DatingLimits.maxVoiceIntroSec)
                )
                dating.apply(try await APIClient.shared.setDatingVoice(attachmentId: attachment.id))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func removeVoice() {
        VoicePlayer.shared.stop()
        Task {
            do {
                dating.apply(try await APIClient.shared.removeDatingVoice())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
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

/// Ролик анкеты перед загрузкой: H.264 mp4 не больше 720p и без метаданных. В оригинале из «Фото» лежат
/// координаты места съёмки, модель телефона и дата — чужим людям из знакомств их видеть незачем.
/// Заодно файл становится в разы меньше, а HEVC (.mov с iPhone) — mp4, который проигрывается везде.
enum ProfileVideoExporter {
    enum ExportError: LocalizedError {
        case failed
        case tooLong(maxSec: Int)

        var errorDescription: String? {
            switch self {
            case .failed: return String(localized: "Не удалось подготовить видео, попробуйте другое")
            case .tooLong(let maxSec): return String(localized: "Видео должно быть не длиннее \(maxSec) секунд")
            }
        }
    }

    /// Длинный ролик отклоняем до перекодирования — незачем минуту жать видео, которое всё равно не подойдёт.
    /// Возвращает временный mp4: удаляет его тот, кто загрузил.
    static func export(_ original: Data, maxDurationSec: Int) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
        let sourceURL = directory.appendingPathComponent("dating-video-\(UUID().uuidString).mov")
        let outputURL = directory.appendingPathComponent("dating-video-\(UUID().uuidString).mp4")
        // AVFoundation работает только с файлами, поэтому ролик сначала ложится во временную папку.
        try original.write(to: sourceURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        var isExported = false
        defer { if !isExported { try? FileManager.default.removeItem(at: outputURL) } }

        let asset = AVURLAsset(url: sourceURL)
        let sourceSeconds = try await asset.load(.duration).seconds
        guard sourceSeconds.isFinite, sourceSeconds > 0 else { throw ExportError.failed }
        guard Int(sourceSeconds.rounded(.up)) <= maxDurationSec else { throw ExportError.tooLong(maxSec: maxDurationSec) }

        // Пресет с размером не растягивает маленькое видео, а только уменьшает большое.
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw ExportError.failed
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.shouldOptimizeForNetworkUse = true
        session.metadata = []
        session.metadataItemFilter = .forSharing()
        await session.export()
        guard session.status == .completed else {
            throw session.error ?? ExportError.failed
        }

        let seconds = try await AVURLAsset(url: outputURL).load(.duration).seconds
        guard seconds.isFinite, seconds > 0 else { throw ExportError.failed }
        isExported = true
        return outputURL
    }
}
