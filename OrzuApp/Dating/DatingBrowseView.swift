import SwiftUI

/// Корень вкладки «Анкеты»: все анкеты нужного пола сеткой, с фильтрами и поиском по @username.
struct DatingBrowseTabView: View {
    @ObservedObject var dating: DatingViewModel

    var body: some View {
        DatingGate(dating: dating, title: "Анкеты") {
            DatingBrowseView(dating: dating)
        }
    }
}

/// Сетка анкет. В отличие от ленты, здесь нет подбора: показываются все, кто подходит под фильтры, новые сверху.
struct DatingBrowseView: View {
    @ObservedObject var dating: DatingViewModel

    @StateObject private var browse = DatingBrowseViewModel()
    @State private var showFilters = false
    @State private var showUsernameSearch = false
    /// Что сделать, когда окно поиска закроется: второе окно поверх закрывающегося SwiftUI не покажет.
    @State private var afterUsernameSearch: (() -> Void)?
    @State private var detailCard: DatingBrowseCard?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        content
            .background(DatingBackdrop())
            .toolbar { toolbarContent }
            // Фильтры поменяли здесь или «Кого ищу» в «Моём профиле» — сетка собирается заново.
            .task(id: ReloadKey(filters: browse.filters, revision: dating.searchSettingsRevision)) { await browse.reload() }
            .task {
                // Разрешили — сетка перезагрузится уже с «N км»: setShowsDistance меняет searchSettingsRevision.
                do {
                    try await dating.askForDistanceIfUndecided()
                } catch {
                    // Ушли с вкладки, пока шёл запрос, — это не ошибка.
                    guard !Task.isCancelled else { return }
                    browse.errorMessage = error.localizedDescription
                }
            }
            .sheet(isPresented: $showFilters) {
                NavigationStack {
                    DatingBrowseFiltersView(filters: browse.filters, catalog: dating.catalog, countryCode: dating.profile?.shared.countryCode) {
                        browse.apply($0)
                    }
                }
            }
            .sheet(isPresented: $showUsernameSearch, onDismiss: {
                afterUsernameSearch?()
                afterUsernameSearch = nil
            }) {
                NavigationStack {
                    DatingUsernameSearchView(catalog: dating.catalog) { card, action in
                        afterUsernameSearch = { handleSearchResult(card, action) }
                        showUsernameSearch = false
                    }
                }
            }
            .sheet(item: $detailCard) { item in
                NavigationStack {
                    DatingProfileDetailView(
                        profile: item.card.profile,
                        catalog: dating.catalog,
                        compatibility: item.card.compatibility,
                        // Уже лайкнули — второй лайк ничего не изменит, кнопку не показываем.
                        onLike: item.liked ? nil : { Task { await browse.like(item.card) } },
                        onIntro: { PushManager.shared.openConversation(with: item.card.profile) }
                    )
                }
            }
            .fullScreenCover(item: $browse.newMatch) { match in
                MatchCelebrationView(match: match, myPhotoId: dating.profile?.shared.photoIds.first) {
                    browse.newMatch = nil
                }
            }
            .alert("Ошибка", isPresented: .constant(browse.errorMessage != nil)) {
                Button("Ок") { browse.errorMessage = nil }
            } message: {
                Text(browse.errorMessage ?? "")
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showUsernameSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Найти по @username")

            Button {
                showFilters = true
            } label: {
                Image(systemName: browse.filters.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    .overlay(alignment: .topTrailing) {
                        if browse.filters.activeCount > 0 {
                            Text("\(browse.filters.activeCount)")
                                .font(.app(.caption2, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(DatingStyle.rose, in: Capsule())
                                .offset(x: 9, y: -7)
                        }
                    }
            }
            .accessibilityLabel(browse.filters.activeCount > 0 ? "Фильтры, выбрано: \(browse.filters.activeCount)" : "Фильтры")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let blocked = browse.blockedMessage {
            ContentUnavailableView("Анкеты закрыты", systemImage: "heart.slash", description: Text(blocked))
        } else if browse.cards.isEmpty {
            if browse.isLoading {
                ProgressView()
                    .tint(DatingStyle.rose)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                emptyState
            }
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(browse.cards) { item in
                    Button {
                        detailCard = item
                    } label: {
                        DatingBrowseTile(item: item, catalog: dating.catalog)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .onAppear {
                        // Последняя плитка на экране — пора догружать следующую страницу.
                        if item.id == browse.cards.last?.id {
                            Task { await browse.loadMore() }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if browse.hasMore {
                ProgressView()
                    .padding(.vertical, 16)
            }
        }
        .refreshable { await browse.reload() }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Никого не нашли", systemImage: "person.2.slash")
        } description: {
            Text(browse.filters.activeCount > 0 ? "Под выбранные фильтры пока никто не подходит." : "Анкет пока нет — загляните позже.")
        } actions: {
            if browse.filters.activeCount > 0 {
                Button("Сбросить фильтры") { browse.apply(DatingBrowseFilters()) }
                    .glassProminentButtonStyle()
                    .tint(DatingStyle.rose)
            }
        }
    }

    private func handleSearchResult(_ card: DatingFeedCard, _ action: DatingSearchAction) {
        switch action {
        case .like: Task { await browse.like(card) }
        case .skip: Task { await browse.skip(card) }
        case .intro: PushManager.shared.openConversation(with: card.profile)
        }
    }

    /// Сетка перезагружается при смене любого из двух: фильтров или «Кого ищу».
    private struct ReloadKey: Equatable {
        let filters: DatingBrowseFilters
        let revision: Int
    }
}

/// Плитка анкеты: главное фото, имя, возраст и город; сердечко — если я уже поставил лайк.
private struct DatingBrowseTile: View {
    let item: DatingBrowseCard
    let catalog: DatingCatalog?

    private var profile: DatingProfilePublic {
        item.card.profile
    }

    var body: some View {
        DatingPhotoView(attachmentId: profile.photoIds.first, cornerRadius: 0)
            .aspectRatio(3 / 4, contentMode: .fit)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .bottomLeading) { caption }
            .overlay(alignment: .topTrailing) { badges }
            .clipShape(RoundedRectangle(cornerRadius: DatingStyle.tileCornerRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: DatingStyle.tileCornerRadius, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(profile.displayName), \(profile.age)")
                    .font(.display(.subheadline))
                    .lineLimit(1)
                if profile.verified {
                    VerifiedBadge()
                        .font(.app(.caption))
                }
            }
            Text(location)
                .font(.app(.caption))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(10)
    }

    @ViewBuilder
    private var badges: some View {
        if item.liked {
            Image(systemName: "heart.fill")
                .font(.app(.footnote, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(DatingStyle.rose, in: Circle())
                .padding(8)
        } else if item.card.isNew {
            DatingChip(text: "Новенький", systemImage: "sparkle", onPhoto: true)
                .padding(8)
        }
    }

    /// Город и, если известно, расстояние: «Душанбе · 3 км».
    private var location: String {
        let city = catalog?.cityName(countryCode: profile.countryCode, cityCode: profile.cityCode) ?? profile.cityCode
        return [city, profile.distanceText].compactMap { $0 }.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = ["\(profile.displayName), \(profile.age)", location]
        if profile.verified { parts.append("проверен") }
        if item.liked { parts.append("вы поставили лайк") }
        return parts.joined(separator: ", ")
    }
}
