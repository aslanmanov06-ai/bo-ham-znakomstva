import Combine
import PhotosUI
import SwiftUI

/// Скрытый альбом: фото, которых нет в анкете и ленте. Их видят только собеседники, которым владелец сам открыл
/// доступ — в ответ на запрос или по своей инициативе; доступ можно отозвать в любой момент.
struct PrivateAlbumView: View {
    @State private var album: PrivateAlbum?
    @State private var isLoading = true
    @State private var isUploading = false
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var errorMessage: String?
    @State private var viewedIndex = 0
    @State private var showViewer = false
    @State private var personPendingRevoke: PrivateAlbumPerson?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    private let maxPhotoDimension: CGFloat = 2048

    var body: some View {
        Form {
            if let album {
                photosSection(album)
                if !album.requests.isEmpty {
                    Section("Просят показать") {
                        ForEach(album.requests) { person in
                            requestRow(person)
                        }
                    }
                }
                if !album.viewers.isEmpty {
                    Section {
                        ForEach(album.viewers) { person in
                            viewerRow(person)
                        }
                    } header: {
                        Text("Альбом открыт")
                    } footer: {
                        Text("После отзыва человек сразу перестаёт видеть альбом. Он сможет попросить доступ снова.")
                    }
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Скрытый альбом")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: photoItems) { _, items in
            if !items.isEmpty { addPhotos(items) }
        }
        // Новый запрос пришёл, пока экран открыт, — список обновляется сам.
        .onReceive(WebSocketClient.shared.events.receive(on: DispatchQueue.main)) { event in
            guard case .privateAlbumChanged = event else { return }
            Task { await load() }
        }
        .fullScreenCover(isPresented: $showViewer) {
            ProfilePhotoViewer(photoIds: album?.photoIds ?? [], index: $viewedIndex)
        }
        .confirmationDialog(
            "Закрыть альбом для \(personPendingRevoke?.user.displayName ?? "")?",
            isPresented: Binding(get: { personPendingRevoke != nil }, set: { if !$0 { personPendingRevoke = nil } }),
            titleVisibility: .visible,
            presenting: personPendingRevoke
        ) { person in
            Button("Отозвать доступ", role: .destructive) { change(person) { try await APIClient.shared.revokePrivateAlbum(userId: person.user.id) } }
        }
    }

    private func photosSection(_ album: PrivateAlbum) -> some View {
        Section {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Array(album.photoIds.enumerated()), id: \.element) { index, photoId in
                    photoCell(photoId, index: index)
                }
                if album.photoIds.count < album.maxPhotos {
                    addCell(remaining: album.maxPhotos - album.photoIds.count)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Фото · \(album.photoIds.count) из \(album.maxPhotos)")
        } footer: {
            Text("Этих фото нет в анкете и ленте. Их видят только собеседники, которым вы сами открыли альбом. Правила сообщества действуют и здесь: на фото можно пожаловаться.")
        }
    }

    private func photoCell(_ photoId: String, index: Int) -> some View {
        DatingPhotoView(attachmentId: photoId, cornerRadius: 14)
            .aspectRatio(3 / 4, contentMode: .fit)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onTapGesture {
                viewedIndex = index
                showViewer = true
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    setPhotos((album?.photoIds ?? []).filter { $0 != photoId })
                } label: {
                    Image(systemName: "xmark")
                        .font(.app(.caption, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(6)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Убрать фото из альбома")
            }
    }

    @ViewBuilder
    private func addCell(remaining: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        if isUploading {
            shape.fill(Color.appElevated)
                .aspectRatio(3 / 4, contentMode: .fit)
                .overlay { ProgressView() }
        } else {
            PhotosPicker(selection: $photoItems, maxSelectionCount: remaining, matching: .images) {
                shape
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(DatingStyle.rose)
                    .background(Color.appElevated.opacity(0.6), in: shape)
                    .aspectRatio(3 / 4, contentMode: .fit)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.app(.title2, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(DatingStyle.brandGradient, in: Circle())
                    }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Добавить фото")
        }
    }

    private func requestRow(_ person: PrivateAlbumPerson) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: person.user.avatarUrl, name: person.user.displayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.user.displayName).font(.app(.body, weight: .semibold))
                Text(person.at.formatted(.relative(presentation: .named))).font(.app(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Отклонить") { change(person) { try await APIClient.shared.revokePrivateAlbum(userId: person.user.id) } }
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .buttonStyle(.borderless)
            Button("Показать") { change(person) { try await APIClient.shared.grantPrivateAlbum(userId: person.user.id) } }
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(Color.brand)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func viewerRow(_ person: PrivateAlbumPerson) -> some View {
        HStack(spacing: 12) {
            AvatarView(avatarUrl: person.user.avatarUrl, name: person.user.displayName, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.user.displayName).font(.app(.body, weight: .semibold))
                Text("открыт \(person.at.formatted(.dateTime.day().month()))").font(.app(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Отозвать") { personPendingRevoke = person }
                .font(.app(.subheadline))
                .foregroundStyle(.red)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Действия

    private func load() async {
        defer { isLoading = false }
        do {
            album = try await APIClient.shared.fetchPrivateAlbum()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addPhotos(_ items: [PhotosPickerItem]) {
        isUploading = true
        Task {
            defer {
                isUploading = false
                photoItems = []
            }
            var ids = album?.photoIds ?? []
            for item in items {
                guard
                    let data = try? await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data),
                    // Фото из библиотеки часто HEIC на десятки МБ — альбому хватает JPEG 2048 px.
                    let jpeg = image.downscaled(maxDimension: maxPhotoDimension).jpegData(compressionQuality: 0.85)
                else {
                    errorMessage = String(localized: "Не удалось прочитать фото")
                    continue
                }
                do {
                    ids.append(try await APIClient.shared.uploadAttachment(data: jpeg, fileName: "photo.jpg", mimeType: "image/jpeg").id)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            await applyPhotos(ids)
        }
    }

    private func setPhotos(_ ids: [String]) {
        Task { await applyPhotos(ids) }
    }

    private func applyPhotos(_ ids: [String]) async {
        guard ids != album?.photoIds else { return }
        do {
            album = try await APIClient.shared.setPrivateAlbumPhotos(attachmentIds: ids)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Показать, отклонить или отозвать: после ответа сервера списки перечитываются целиком.
    private func change(_ person: PrivateAlbumPerson, _ action: @escaping () async throws -> Void) {
        Task {
            do {
                try await action()
                await load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Скрытые альбомы двоих собеседников для карточки в анкете. Состояние живёт выше карточки: пока альбомов нет
/// (или человек не собеседник), карточки в анкете нет вовсе — а у вида без содержимого не сработал бы и .task.
@MainActor
final class PartnerAlbumModel: ObservableObject {
    @Published private(set) var album: PartnerAlbum?
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    /// Есть что показать: альбом хотя бы у одного из двоих.
    var isVisible: Bool { album.map { !$0.isEmpty } ?? false }

    func load(userId: String) async {
        do {
            album = try await APIClient.shared.fetchPartnerAlbum(userId: userId)
        } catch {
            // Не собеседник, заблокирован или сервер ещё без альбомов — карточки нет, ошибку показывать не о чем.
            album = nil
        }
    }

    func request(userId: String) {
        run(userId) { _ = try await APIClient.shared.requestPartnerAlbum(userId: userId) }
    }

    func grant(userId: String) {
        run(userId) { try await APIClient.shared.grantPrivateAlbum(userId: userId) }
    }

    func revoke(userId: String) {
        run(userId) { try await APIClient.shared.revokePrivateAlbum(userId: userId) }
    }

    /// Действие с альбомом: после ответа сервера карточка перечитывается, ошибка показывается в ней же.
    private func run(_ userId: String, _ action: @escaping () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                try await action()
                errorMessage = nil
                await load(userId: userId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Карточка в анкете собеседника: его скрытый альбом (попросить и посмотреть) и мой — для него (показать и отозвать).
struct PartnerAlbumCard: View {
    @ObservedObject var model: PartnerAlbumModel
    let userId: String
    let displayName: String

    @State private var viewedIndex = 0
    @State private var showViewer = false
    @State private var confirmRevoke = false

    var body: some View {
        DatingSectionCard(title: String(localized: "Скрытый альбом"), systemImage: "lock.fill") {
            VStack(alignment: .leading, spacing: 14) {
                if let album = model.album {
                    if album.theirs.photoCount > 0 { theirs(album.theirs) }
                    if album.theirs.photoCount > 0 && album.mine.photoCount > 0 { Divider() }
                    if album.mine.photoCount > 0 { mine(album.mine) }
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).font(.app(.footnote)).foregroundStyle(.red)
                }
            }
        }
        .fullScreenCover(isPresented: $showViewer) {
            ProfilePhotoViewer(photoIds: model.album?.theirs.photoIds ?? [], index: $viewedIndex)
        }
        .confirmationDialog("Закрыть альбом для \(displayName)?", isPresented: $confirmRevoke, titleVisibility: .visible) {
            Button("Отозвать доступ", role: .destructive) { model.revoke(userId: userId) }
        }
    }

    @ViewBuilder
    private func theirs(_ theirs: PartnerAlbum.Theirs) -> some View {
        switch theirs.status {
        case .granted:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(theirs.photoIds.enumerated()), id: \.element) { index, photoId in
                        DatingPhotoView(attachmentId: photoId, cornerRadius: 14)
                            .frame(width: 96, height: 128)
                            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .onTapGesture {
                                viewedIndex = index
                                showViewer = true
                            }
                            .accessibilityLabel("Фото из скрытого альбома")
                    }
                }
            }
        case .pending:
            statusLine(String(localized: "Запрос отправлен. Фото появятся, когда \(displayName) откроет альбом."), systemImage: "clock")
        case .declined:
            statusLine(String(localized: "Запрос отклонён. Повторить можно через сутки."), systemImage: "xmark.circle")
        case .none:
            VStack(alignment: .leading, spacing: 10) {
                Text("В альбоме \(theirs.photoCount) фото. Их видно только с разрешения владельца.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                actionButton(String(localized: "Попросить показать"), prominent: true) { model.request(userId: userId) }
            }
        }
    }

    @ViewBuilder
    private func mine(_ mine: PartnerAlbum.Mine) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch mine.status {
            case .granted:
                statusLine(String(localized: "Ваш альбом открыт для \(displayName)."), systemImage: "eye")
                actionButton(String(localized: "Отозвать доступ"), prominent: false) { confirmRevoke = true }
            case .pending:
                statusLine(String(localized: "\(displayName) просит показать ваш альбом."), systemImage: "hand.raised")
                HStack(spacing: 10) {
                    actionButton(String(localized: "Показать"), prominent: true) { model.grant(userId: userId) }
                    actionButton(String(localized: "Отклонить"), prominent: false) { model.revoke(userId: userId) }
                }
            case .none, .declined:
                statusLine(String(localized: "Ваш скрытый альбом для \(displayName) закрыт."), systemImage: "lock")
                actionButton(String(localized: "Показать мой альбом"), prominent: false) { model.grant(userId: userId) }
            }
        }
    }

    private func statusLine(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.app(.subheadline))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func actionButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.brand)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(prominent ? AnyShapeStyle(DatingStyle.brandGradient) : AnyShapeStyle(Color.brandSoft), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(model.isBusy)
    }
}

/// Запись о скрытом альбоме в переписке: кто попросил или открыл альбом, а под ней — ответ на запрос или «Посмотреть».
struct AlbumEventRow: View {
    let text: String
    let action: AlbumEventAction?
    let isBusy: Bool
    let errorMessage: String?
    let onGrant: () -> Void
    let onDecline: () -> Void
    let onView: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Label(text, systemImage: "lock.fill")
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            switch action {
            case .answerRequest:
                HStack(spacing: 10) {
                    button(String(localized: "Показать"), prominent: true, action: onGrant)
                    button(String(localized: "Отклонить"), prominent: false, action: onDecline)
                }
            case .viewAlbum:
                button(String(localized: "Посмотреть"), prominent: true, action: onView)
            case nil:
                EmptyView()
            }
            if action != nil, let errorMessage {
                Text(errorMessage).font(.app(.caption)).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, action == nil ? 6 : 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: action == nil ? 16 : 18, style: .continuous))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func button(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(prominent ? Color.white : Color.brand)
                .padding(.horizontal, 18)
                .padding(.vertical, 9)
                .background(prominent ? AnyShapeStyle(DatingStyle.brandGradient) : AnyShapeStyle(Color.brandSoft), in: Capsule())
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isBusy)
    }
}
