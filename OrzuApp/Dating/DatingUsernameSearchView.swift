import SwiftUI

enum DatingSearchAction {
    case like, skip, intro
}

/// Найти анкету знакомого человека по точному @username. Частичного совпадения нет намеренно:
/// иначе поиском можно было бы листать анкеты в обход ленты.
struct DatingUsernameSearchView: View {
    let catalog: DatingCatalog?
    /// Лайк, пропуск или первое сообщение из найденной анкеты — выполняет лента, когда это окно закроется.
    let onAction: (DatingFeedCard, DatingSearchAction) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    /// nil — ещё не искали; пустой массив — не нашли.
    @State private var results: [DatingFeedCard]?
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("username", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                }
                Button {
                    Task { await search() }
                } label: {
                    if isSearching { ProgressView() } else { Text("Найти") }
                }
                .disabled(!UsernameRules.isValid(username) || isSearching)
            } footer: {
                Text("Только точный username. Анкету не найти, если человек запретил поиск по username или скрыл её.")
            }

            if let results {
                Section {
                    if results.isEmpty {
                        Text("Анкета не найдена").foregroundStyle(.secondary)
                    }
                    ForEach(results) { card in
                        NavigationLink {
                            detail(card)
                        } label: {
                            row(card)
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Поиск по username")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .onChange(of: query) { _, _ in
            results = nil
            errorMessage = nil
        }
    }

    private var username: String {
        UsernameRules.normalized(query)
    }

    private func search() async {
        guard UsernameRules.isValid(username), !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await APIClient.shared.searchDatingProfiles(username: username)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func row(_ card: DatingFeedCard) -> some View {
        HStack(spacing: 12) {
            DatingPhotoView(attachmentId: card.profile.photoIds.first, cornerRadius: 22)
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(card.profile.displayName), \(card.profile.age)").font(.app(.headline))
                Text(location(card.profile))
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func location(_ profile: DatingProfilePublic) -> String {
        let city = catalog?.cityName(countryCode: profile.countryCode, cityCode: profile.cityCode) ?? profile.cityCode
        return [city, profile.distanceText].compactMap { $0 }.joined(separator: " · ")
    }

    private func detail(_ card: DatingFeedCard) -> some View {
        DatingProfileDetailView(
            profile: card.profile,
            catalog: catalog,
            compatibility: card.compatibility,
            onLike: { onAction(card, .like) },
            onSkip: { onAction(card, .skip) },
            onIntro: { onAction(card, .intro) }
        )
    }
}
