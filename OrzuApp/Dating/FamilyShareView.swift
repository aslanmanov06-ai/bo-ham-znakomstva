import SwiftUI

/// «Показать анкету семье»: ссылка со сроком жизни, по которой родные видят анкету без приложения и входа —
/// имя, возраст, город, одобренные фото и рассказ о себе, без @username и контактов. Ссылку можно отозвать.
struct FamilyShareView: View {
    @State private var links: [ProfileShareLink] = []
    @State private var created: CreatedProfileShareLink?
    @State private var duration: ProfileShareDuration = .week
    @State private var isLoading = true
    @State private var isCreating = false
    @State private var copied = false
    @State private var errorMessage: String?
    @State private var linkPendingRevoke: ProfileShareLink?

    var body: some View {
        Form {
            Section {
                Picker("Срок действия", selection: $duration) {
                    ForEach(ProfileShareDuration.allCases) { Text($0.title).tag($0) }
                }
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        SettingsLabel(String(localized: "Создать ссылку"), systemImage: "link.badge.plus", color: .brand)
                        Spacer()
                        if isCreating { ProgressView() }
                    }
                }
                .disabled(isCreating)
            } footer: {
                Text("По ссылке анкету можно посмотреть без приложения: имя, возраст, город, одобренные фото, рассказ о себе и интересы. Логин, контакты и переписка не показываются.")
            }
            .tint(.primary)

            if let created {
                createdSection(created)
            }

            if !links.isEmpty {
                Section {
                    ForEach(links) { link in
                        row(link)
                    }
                } header: {
                    Text("Действующие ссылки")
                } footer: {
                    Text("Отозванная ссылка перестаёт открываться сразу. Адрес показывается только при создании — если он потерян, отзовите ссылку и создайте новую.")
                }
            } else if isLoading {
                ProgressView().frame(maxWidth: .infinity)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Показать анкету семье")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sensoryFeedback(.success, trigger: copied) { _, isCopied in isCopied }
        .confirmationDialog(
            "Отозвать ссылку?",
            isPresented: Binding(get: { linkPendingRevoke != nil }, set: { if !$0 { linkPendingRevoke = nil } }),
            titleVisibility: .visible,
            presenting: linkPendingRevoke
        ) { link in
            Button("Отозвать", role: .destructive) { Task { await revoke(link) } }
        } message: { _ in
            Text("Те, у кого она есть, больше не смогут открыть анкету.")
        }
    }

    private func createdSection(_ link: CreatedProfileShareLink) -> some View {
        Section {
            Text(link.url.absoluteString)
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            ShareLink(item: link.url) {
                SettingsLabel(String(localized: "Отправить"), systemImage: "square.and.arrow.up", color: .brand)
            }
            Button {
                UIPasteboard.general.url = link.url
                copied = true
            } label: {
                SettingsLabel(
                    copied ? String(localized: "Скопировано") : String(localized: "Скопировать ссылку"),
                    systemImage: copied ? "checkmark" : "doc.on.doc", color: .champagne
                )
            }
        } header: {
            Text("Новая ссылка")
        } footer: {
            Text("Действует до \(link.expiresAt.formatted(.dateTime.day().month().year())). Сохраните или отправьте её сейчас: позже адрес не показать.")
        }
        .tint(.primary)
    }

    private func row(_ link: ProfileShareLink) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.champagne)
                .frame(width: 38, height: 38)
                .background(Color.champagne.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("До \(link.expiresAt.formatted(.dateTime.day().month()))")
                    .font(.app(.body, weight: .semibold))
                Text("создана \(link.createdAt.formatted(.dateTime.day().month()))")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Отозвать") { linkPendingRevoke = link }
                .font(.app(.subheadline))
                .foregroundStyle(.red)
                .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            links = try await APIClient.shared.fetchProfileShareLinks()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let link = try await APIClient.shared.createProfileShareLink(days: duration.rawValue)
            copied = false
            created = link
            links.insert(ProfileShareLink(id: link.id, createdAt: Date(), expiresAt: link.expiresAt), at: 0)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ link: ProfileShareLink) async {
        do {
            try await APIClient.shared.revokeProfileShareLink(id: link.id)
            links.removeAll { $0.id == link.id }
            if created?.id == link.id { created = nil }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
