import SwiftUI

/// Корень вкладки «Поиск»: все анкеты нужного пола сеткой, с фильтрами и поиском по @username.
struct DatingBrowseTabView: View {
    @ObservedObject var dating: DatingViewModel

    var body: some View {
        DatingGate(dating: dating, title: String(localized: "Поиск")) {
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
    /// Подсказку «фильтр — только здесь» закрывают крестиком, и она больше не появляется.
    @AppStorage("dating.browseHintClosed") private var hintClosed = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        VStack(spacing: 0) {
            header
            if !hintClosed {
                hint
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            filterBar
                .padding(.bottom, 6)
            content
                .frame(maxHeight: .infinity)
        }
        .animation(DatingStyle.spring, value: hintClosed)
        .background(DatingBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        // Фильтры поменяли здесь или «Кого ищу» в профиле — сетка собирается заново.
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
                DatingBrowseFiltersView(filters: browse.filters, catalog: dating.catalog, countryCode: dating.profile?.shared.countryCode, lookingFor: dating.lookingFor) {
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
                    viewer: dating.profile?.shared,
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

    private var header: some View {
        HStack {
            Text("Поиск")
                .font(.display(size: 30, weight: .bold))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showUsernameSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Найти по @username")
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// Чем «Поиск» отличается от ленты: люди путали фильтр здесь с «Кого ищу».
    private var hint: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.brand)
                .padding(.top, 1)
            Text("Все анкеты — ищите сами по фильтрам. Фильтр действует только здесь: на ленту «Знакомства» он не влияет.")
                .font(.app(.subheadline))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                hintClosed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть подсказку")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.brand.opacity(0.4), lineWidth: 1))
    }

    /// «Фильтр · 4» и чипы того, что выбрано, — видно, почему в сетке именно эти люди.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    showFilters = true
                } label: {
                    Label {
                        Text(browse.filters.activeCount > 0 ? "Фильтр · \(browse.filters.activeCount)" : "Фильтр")
                    } icon: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(.brandFill, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel(browse.filters.activeCount > 0 ? "Фильтры, выбрано: \(browse.filters.activeCount)" : "Фильтры")

                ForEach(filterChips, id: \.self) { chip in
                    Button {
                        showFilters = true
                    } label: {
                        Text(chip)
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .background(Color.appSurface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    /// Самые понятные из выбранных фильтров: возраст, город, расстояние, дети.
    private var filterChips: [String] {
        let filters = browse.filters
        var chips: [String] = []
        switch (filters.ageMin, filters.ageMax) {
        case let (min?, max?): chips.append(String(localized: "\(min)–\(max) лет"))
        case let (min?, nil): chips.append(String(localized: "от \(min) лет"))
        case let (nil, max?): chips.append(String(localized: "до \(max) лет"))
        case (nil, nil): break
        }
        if let cityCode = filters.cityCode {
            let countryCode = dating.profile?.shared.countryCode ?? ""
            chips.append(dating.catalog?.cityName(countryCode: countryCode, cityCode: cityCode) ?? cityCode)
        }
        if let distance = filters.maxDistanceKm {
            chips.append(String(localized: "до \(distance) км"))
        }
        switch filters.children {
        case "NONE": chips.append(String(localized: "Без детей"))
        case "HAS": chips.append(String(localized: "С детьми"))
        default: break
        }
        return chips
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
                    .font(.display(size: 17, weight: .bold))
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
            DatingChip(text: String(localized: "Новенький"), systemImage: "sparkle", onPhoto: true)
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
        if profile.verified { parts.append(String(localized: "проверен")) }
        if item.liked { parts.append(String(localized: "вы поставили лайк")) }
        return parts.joined(separator: ", ")
    }
}
