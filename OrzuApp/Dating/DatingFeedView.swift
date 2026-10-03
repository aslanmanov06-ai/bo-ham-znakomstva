import SwiftUI

/// Куда улетает карточка после жеста.
enum SwipeDirection: Equatable {
    case like
    case skip

    /// Решаем по точке, куда карточка долетела бы по инерции: короткий резкий бросок засчитывается,
    /// а если палец зашёл за порог и отдёрнул карточку назад — свайп отменяется.
    static func decide(predictedEndX: CGFloat, threshold: CGFloat) -> SwipeDirection? {
        if predictedEndX >= threshold { return .like }
        if predictedEndX <= -threshold { return .skip }
        return nil
    }
}

/// Лента знакомств: подходящие анкеты большой карточкой, оценка кнопками с подписями или жестом.
/// Фильтров здесь нет намеренно — подбор делает сервер; фильтры и поиск по @username — во вкладке «Поиск».
/// Пары и первые сообщения живут во вкладке «Чаты», отсюда туда не ведём — так переписка в одном месте.
struct DatingFeedView: View {
    @ObservedObject var dating: DatingViewModel
    let onOpenSearch: () -> Void
    let onOpenRoulette: () -> Void

    @StateObject private var feed = DatingFeedViewModel()
    @ObservedObject private var push = PushManager.shared
    @StateObject private var likes = LikedMeViewModel()
    @State private var showLikedMe = false
    @State private var showProfileEditor = false
    @State private var showCriteria = false
    @State private var detailCard: DatingFeedCard?
    /// Кому собираются написать, пока открыт лист «Как работает „Написать“».
    @State private var introCard: DatingFeedCard?
    @State private var showHint = false
    @State private var showHowItWorks = false
    /// Подсказка под ⓘ появляется сама один раз, дальше — по нажатию.
    @AppStorage("dating.feedHintShown") private var feedHintShown = false
    /// Лист про «Написать» показываем перед первым сообщением, потом пишем сразу.
    @AppStorage("dating.introExplained") private var introExplained = false
    @State private var dragOffset: CGSize = .zero
    /// Карточки, которые уже улетели, но ответ сервера ещё не пришёл: из стопки их прячем сразу.
    @State private var departingCardIds: Set<String> = []
    @State private var pastThreshold = false
    /// Карточка в полёте: второй тап или жест в это время не должен отправить оценку повторно.
    @State private var flyingCardId: String?
    @State private var stackWidth: CGFloat = 0

    private let swipeThreshold: CGFloat = 110
    /// Сколько карточек видно в стопке: верхняя и две выглядывают из-под неё.
    private let stackDepth = 3
    private let prefetchDepth = 4
    /// Высота кнопок с подписями поверх низа карточки: текст анкеты начинается выше них.
    private static let actionAreaHeight: CGFloat = 112
    /// Остаток лайков показываем, только когда их мало: в остальное время цифры — в подсказке ⓘ.
    private static let lowLikesThreshold = 3

    var body: some View {
        VStack(spacing: 0) {
            header
            if let profile = dating.profile, !profile.visibleToOthers {
                visibilityBanner(profile)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
            }
            if let limits = feed.limits, limits.likesLeft <= Self.lowLikesThreshold, feed.blockedMessage == nil {
                limitsLabel(limits)
                    .padding(.bottom, 6)
            }
            content
        }
        .overlay(alignment: .topTrailing) {
            if showHint {
                hintBubble
            }
        }
        .background(DatingBackdrop())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showLikedMe) {
            LikedMeView(likes: likes, dating: dating)
        }
        .navigationDestination(isPresented: $showHowItWorks) {
            HowItWorksView()
        }
        .task(id: dating.searchSettingsRevision) {
            await feed.load()
            await likes.load()
        }
        .task { await showHintOnce() }
        // Строка «Сейчас: 22–30 лет» на пустой ленте.
        .task { if dating.criteria == nil { try? await dating.loadCriteria() } }
        .task(id: visibleCards.first?.id) { prefetchUpcomingPhotos() }
        // Нажали на push «Вас лайкнули».
        .task(id: push.pendingLikedMe) {
            guard push.pendingLikedMe else { return }
            push.pendingLikedMe = false
            showLikedMe = true
        }
        .sensoryFeedback(.selection, trigger: pastThreshold) { _, isPast in isPast }
        .sheet(isPresented: $showProfileEditor) {
            NavigationStack { DatingProfileEditorView(dating: dating) }
        }
        .sheet(isPresented: $showCriteria) {
            NavigationStack { SearchCriteriaView(dating: dating) {} }
        }
        .sheet(item: $introCard) { card in
            IntroExplainerSheet(name: card.profile.displayName, limits: feed.limits) {
                introExplained = true
                introCard = nil
                PushManager.shared.openConversation(with: card.profile)
            }
        }
        .sheet(item: $detailCard) { card in
            NavigationStack {
                DatingProfileDetailView(
                    profile: card.profile,
                    catalog: dating.catalog,
                    compatibility: card.compatibility,
                    viewer: dating.profile?.shared,
                    onLike: { send(card, .like) },
                    onSkip: { send(card, .skip) },
                    onIntro: { PushManager.shared.openConversation(with: card.profile) }
                )
            }
        }
        .fullScreenCover(item: $feed.newMatch) { match in
            MatchCelebrationView(match: match, myPhotoId: dating.profile?.shared.photoIds.first) {
                feed.newMatch = nil
            }
        }
        .alert("Ошибка", isPresented: .constant(feed.errorMessage != nil)) {
            Button("Ок") { feed.errorMessage = nil }
        } message: {
            Text(feed.errorMessage ?? "")
        }
    }

    /// Заголовок вкладки, кто лайкнул и ⓘ — одной строкой, чтобы карточке досталось больше места.
    private var header: some View {
        HStack(spacing: 10) {
            Text("Знакомства")
                .font(.display(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if !likes.cards.isEmpty && feed.blockedMessage == nil {
                LikedMeChip(cards: likes.cards) { showLikedMe = true }
            }
            Button {
                withAnimation(DatingStyle.spring) { showHint.toggle() }
            } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Как работает лента")
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    /// Облачко под ⓘ: чем лента отличается от «Поиска» и сколько лайков и сообщений осталось на сегодня.
    private var hintBubble: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Здесь только те, кто подходит вам — и кому подходите вы. Искать самим — во вкладке «Поиск».")
                    .font(.app(.subheadline))
                    .fixedSize(horizontal: false, vertical: true)
                if let limits = feed.limits {
                    Text(limitsText(limits))
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    showHint = false
                    showHowItWorks = true
                } label: {
                    HStack(spacing: 4) {
                        Text("Как это работает")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(Color.brand)
                }
                .buttonStyle(.plain)
            }
            Button {
                withAnimation(DatingStyle.spring) { showHint = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Закрыть подсказку")
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 12)
        .frame(maxWidth: 300, alignment: .leading)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.brand.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 18, y: 8)
        .padding(.top, 58)
        .padding(.trailing, 12)
        .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
    }

    private func showHintOnce() async {
        guard !feedHintShown else { return }
        feedHintShown = true
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        withAnimation(DatingStyle.spring) { showHint = true }
    }

    @ViewBuilder
    private var content: some View {
        if let blocked = feed.blockedMessage {
            ContentUnavailableView("Лента закрыта", systemImage: "heart.slash", description: Text(blocked))
        } else if visibleCards.isEmpty {
            if feed.isLoading {
                SkeletonCard()
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            } else {
                EmptyFeedView(
                    criteriaLine: criteriaLine,
                    matchingCount: feed.matchingCount,
                    rouletteOnline: feed.rouletteOnline,
                    canUndo: feed.canUndo,
                    onExpandCriteria: { showCriteria = true },
                    onOpenSearch: onOpenSearch,
                    onOpenRoulette: onOpenRoulette,
                    onUndo: { Task { await feed.undo() } },
                    onRefresh: { Task { await feed.load() } }
                )
                .task { await feed.loadEmptyFeedStats() }
            }
        } else {
            cardStack
        }
    }

    /// «Сейчас: 22–30 лет, Душанбе» — что именно расширять в «Кого ищу».
    private var criteriaLine: String? {
        guard let criteria = dating.criteria, criteria.criteriaSetAt != nil else { return nil }
        var parts = [String(localized: "\(criteria.ageMin)–\(criteria.ageMax) лет")]
        if let countryCode = dating.profile?.shared.countryCode {
            let cities = criteria.cityCodes.map { dating.catalog?.cityName(countryCode: countryCode, cityCode: $0) ?? $0 }
            if !cities.isEmpty { parts.append(cities.joined(separator: ", ")) }
        }
        return String(localized: "Сейчас: \(parts.joined(separator: ", "))")
    }

    private var visibleCards: [DatingFeedCard] {
        feed.cards.filter { !departingCardIds.contains($0.id) }
    }

    /// Доля пути до порога свайпа со знаком: +1 — «нравится», −1 — «пропустить».
    private var swipeProgress: CGFloat {
        min(max(dragOffset.width / swipeThreshold, -1), 1)
    }

    private var cardStack: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Array(visibleCards.prefix(stackDepth).enumerated()).reversed(), id: \.element.id) { index, card in
                    let isTop = index == 0
                    DatingCardView(
                        card: card,
                        catalog: dating.catalog,
                        swipeProgress: isTop ? swipeProgress : 0,
                        bottomInset: Self.actionAreaHeight
                    ) {
                        detailCard = card
                    }
                    .scaleEffect(stackScale(at: index))
                    .offset(y: stackOffset(at: index))
                    .offset(isTop ? dragOffset : .zero)
                    .rotationEffect(.degrees(isTop ? Double(dragOffset.width) / 22 : 0), anchor: .bottom)
                    .allowsHitTesting(isTop)
                    .gesture(dragGesture(for: card))
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .accessibilityAction(named: "Нравится") { send(card, .like) }
                    .accessibilityAction(named: "Пропустить") { send(card, .skip) }
                    .accessibilityAction(named: "Написать") { write(card) }
                }
            }
            .onAppear { stackWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in stackWidth = width }
        }
        // Кнопки лежат поверх карточки, но не двигаются вместе с ней: улетает анкета, а не кнопки.
        .overlay(alignment: .bottom) {
            if let card = visibleCards.first {
                actionRow(for: card)
                    .padding(.bottom, 14)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if feed.canUndo {
                undoButton
                    .padding(.leading, 12)
                    .padding(.bottom, 46)
            }
        }
        .animation(DatingStyle.spring, value: feed.canUndo)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Нижние карточки подрастают по мере того, как тянут верхнюю: когда она улетит,
    /// следующая уже стоит на её месте и стопка не «прыгает».
    private func stackScale(at index: Int) -> CGFloat {
        guard index > 0 else { return 1 }
        return 1 - CGFloat(index) * 0.05 + abs(swipeProgress) * 0.05
    }

    private func stackOffset(at index: Int) -> CGFloat {
        guard index > 0 else { return 0 }
        return CGFloat(index) * 14 - abs(swipeProgress) * 14
    }

    /// Под каждой кнопкой — что она делает: значки без слов новичку непонятны.
    private func actionRow(for card: DatingFeedCard) -> some View {
        HStack(alignment: .top, spacing: 24) {
            FeedAction(title: String(localized: "Дальше")) {
                DatingActionButton(kind: .skip, size: 56, onPhoto: true) { send(card, .skip) }
                    .scaleEffect(1 + max(-swipeProgress, 0) * 0.15)
            }
            FeedAction(title: String(localized: "Нравится")) {
                DatingActionButton(kind: .like, size: 68) { send(card, .like) }
                    .scaleEffect(1 + max(swipeProgress, 0) * 0.15)
            }
            FeedAction(title: String(localized: "Написать")) {
                DatingActionButton(kind: .intro, size: 56, onPhoto: true) { write(card) }
            }
        }
        .transition(.opacity)
    }

    private var undoButton: some View {
        Button {
            Task { await feed.undo() }
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color.champagne)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.35), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(feed.isUndoing)
        .accessibilityLabel("Вернуть предыдущую анкету")
        .transition(.scale.combined(with: .opacity))
    }

    private func limitsLabel(_ limits: DailyLimits) -> some View {
        HStack(spacing: 6) {
            Image(systemName: limits.likesLeft == 0 ? "hourglass" : "heart.fill")
                .foregroundStyle(DatingStyle.rose)
            Text(limitsText(limits))
                .contentTransition(.numericText())
        }
        .font(.app(.caption, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .glassSurface(in: Capsule())
        .animation(.snappy, value: limits)
    }

    private func visibilityBanner(_ profile: DatingProfileMine) -> some View {
        Button {
            showProfileEditor = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .font(.app(.title3))
                    .foregroundStyle(Color.champagne)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Вашу анкету не видят другие")
                        .font(.app(.footnote, weight: .semibold))
                    if let issue = profile.visibilityIssues.first {
                        Text(issue.explanation)
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.champagneSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func limitsText(_ limits: DailyLimits) -> String {
        if limits.likesLeft == 0 {
            return String(localized: "Лайки закончились — вернутся \(limits.resetsAt.formatted(date: .omitted, time: .shortened))")
        }
        return String(localized: "Лайков сегодня: \(limits.likesLeft) из \(limits.likesPerDay) · сообщений: \(limits.introsLeft) из \(limits.introsPerDay)")
    }

    /// Перед первым «Написать» объясняем, что будет с сообщением; дальше — сразу к переписке.
    private func write(_ card: DatingFeedCard) {
        if introExplained {
            PushManager.shared.openConversation(with: card.profile)
        } else {
            introCard = card
        }
    }

    private func dragGesture(for card: DatingFeedCard) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard flyingCardId == nil else { return }
                dragOffset = value.translation
                pastThreshold = abs(value.translation.width) >= swipeThreshold
            }
            .onEnded { value in
                guard flyingCardId == nil else { return }
                pastThreshold = false
                if let direction = SwipeDirection.decide(predictedEndX: value.predictedEndTranslation.width, threshold: swipeThreshold) {
                    flyAway(card, direction, verticalDrift: value.predictedEndTranslation.height)
                } else {
                    withAnimation(DatingStyle.spring) { dragOffset = .zero }
                }
            }
    }

    /// Оценка с кнопки или из открытой анкеты: карточка улетает так же, как от жеста.
    private func send(_ card: DatingFeedCard, _ direction: SwipeDirection) {
        detailCard = nil
        // Из открытой анкеты можно оценить не верхнюю карточку — тогда просто убираем её без полёта.
        guard card.id == visibleCards.first?.id else {
            rate(card, direction)
            return
        }
        flyAway(card, direction, verticalDrift: -40)
    }

    private func flyAway(_ card: DatingFeedCard, _ direction: SwipeDirection, verticalDrift: CGFloat) {
        guard flyingCardId == nil else { return }
        flyingCardId = card.id
        let sign: CGFloat = direction == .like ? 1 : -1
        // Улетает на полторы ширины стопки: с поворотом карточка гарантированно скрывается за краем экрана.
        let target = CGSize(width: sign * stackWidth * 1.6, height: dragOffset.height + verticalDrift * 0.3)
        withAnimation(.easeOut(duration: 0.28)) {
            dragOffset = target
        } completion: {
            // Прячем карточку и возвращаем смещение в одной транзакции без анимации: следующая карточка
            // к этому моменту уже доросла до полного размера, поэтому подмена незаметна.
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                departingCardIds.insert(card.id)
                dragOffset = .zero
            }
            flyingCardId = nil
            rate(card, direction)
        }
    }

    private func rate(_ card: DatingFeedCard, _ direction: SwipeDirection) {
        Task {
            switch direction {
            case .like: await feed.like(card)
            case .skip: await feed.skip(card)
            }
            // Если сервер ответил ошибкой, модель вернула карточку в ленту — снова показываем её.
            departingCardIds.remove(card.id)
            if feed.cards.isEmpty {
                await feed.load()
            }
        }
    }

    private func prefetchUpcomingPhotos() {
        let upcoming = visibleCards.prefix(prefetchDepth).flatMap(\.profile.photoIds)
        DatingPhotoView.prefetch(upcoming)
    }
}

/// Карточка кандидата на весь экран: фото листаются тапом по краям, сверху — совместимость,
/// снизу — имя и главное об анкете, а под ними место для кнопок ленты.
private struct DatingCardView: View {
    let card: DatingFeedCard
    let catalog: DatingCatalog?
    /// −1…1: насколько карточку утянули влево или вправо — от этого зависят штампы и подсветка.
    let swipeProgress: CGFloat
    /// Сколько снизу занимают кнопки ленты поверх карточки.
    let bottomInset: CGFloat
    let onOpen: () -> Void

    @State private var photoIndex = 0
    @State private var edgeTilt: Double = 0
    @State private var edgeBumps = 0

    private let visibleInterests = 2

    var body: some View {
        ZStack(alignment: .bottom) {
            DatingPhotoView(attachmentId: currentPhotoId, cornerRadius: 0)
                .overlay { photoTapZones }

            scrim
                .allowsHitTesting(false)

            info
        }
        .overlay(alignment: .top) {
            VStack(alignment: .leading, spacing: 10) {
                photoPager
                badges
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
        .overlay { swipeStamps }
        .clipShape(RoundedRectangle(cornerRadius: DatingStyle.cardCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DatingStyle.cardCornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
        .rotation3DEffect(.degrees(edgeTilt), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .sensoryFeedback(.selection, trigger: photoIndex)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: edgeBumps)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen() }
    }

    private var photoIds: [String] {
        card.profile.photoIds
    }

    private var currentPhotoId: String? {
        photoIds.indices.contains(photoIndex) ? photoIds[photoIndex] : photoIds.first
    }

    private var photoTapZones: some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showPhoto(at: photoIndex - 1) }
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showPhoto(at: photoIndex + 1) }
        }
    }

    /// Дальше фото нет — карточка слегка «упирается», как страница в конце книги.
    private func showPhoto(at index: Int) {
        guard photoIds.indices.contains(index) else {
            edgeBumps += 1
            let direction: Double = index < 0 ? -1 : 1
            withAnimation(.spring(response: 0.15, dampingFraction: 0.5)) {
                edgeTilt = direction * 6
            } completion: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { edgeTilt = 0 }
            }
            return
        }
        photoIndex = index
    }

    @ViewBuilder
    private var photoPager: some View {
        if photoIds.count > 1 {
            HStack(spacing: 4) {
                ForEach(photoIds.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == photoIndex ? Color.white : Color.white.opacity(0.35))
                        .frame(height: 3.5)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 2)
            .animation(.easeOut(duration: 0.2), value: photoIndex)
            .allowsHitTesting(false)
        }
    }

    private var scrim: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 90)
            Spacer()
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.55), location: 0.45),
                    .init(color: .black.opacity(0.85), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260 + bottomInset)
        }
    }

    private var info: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(card.profile.displayName), \(card.profile.age)")
                        .font(.display(size: 32, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if card.profile.verified {
                        VerifiedBadge()
                            .font(.app(.title3))
                    }
                }
                if !subtitle.isEmpty {
                    Label(subtitle, systemImage: "mappin.and.ellipse")
                        .font(.app(.callout, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }
                chips
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, bottomInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Открыть анкету целиком")
    }

    /// Совместимость — золотой пилюлей сверху: это первое, на что смотрят, и фото она не закрывает.
    private var badges: some View {
        HStack(spacing: 6) {
            Text("\(min(max(card.compatibility.score, 0), 100))% совместимость")
                .font(.app(.footnote, weight: .bold))
                .foregroundStyle(Color(rgb: 0x120E12))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color(rgb: 0xF0C27B), in: Capsule())
            if let activity = card.profile.activityStatus {
                ActivityChip(activity: activity, onPhoto: true)
            }
            if card.isNew {
                DatingChip(text: String(localized: "Новенький"), systemImage: "sparkle", onPhoto: true)
            }
            if card.expanded {
                DatingChip(text: String(localized: "Шире фильтров"), systemImage: "arrow.up.left.and.arrow.down.right", onPhoto: true)
            }
        }
        .lineLimit(1)
        .allowsHitTesting(false)
    }

    private var chips: some View {
        let goal = catalog?.relationshipGoals.name(of: card.profile.relationshipGoal)
        let interests = catalog?.names(of: card.profile.interests, in: catalog?.interests ?? []) ?? []
        return FlowLayout(spacing: 6) {
            if let goal {
                DatingChip(text: goal, onPhoto: true)
            }
            ForEach(interests.prefix(visibleInterests), id: \.self) { interest in
                DatingChip(text: interest, onPhoto: true)
            }
        }
    }

    private var swipeStamps: some View {
        ZStack {
            DatingStyle.rose
                .opacity(Double(max(swipeProgress, 0)) * 0.22)
            Color.black
                .opacity(Double(max(-swipeProgress, 0)) * 0.25)
            HStack(alignment: .top) {
                SwipeStamp(text: String(localized: "НРАВИТСЯ"), angle: -14, progress: max(swipeProgress, 0), isLike: true)
                Spacer()
                SwipeStamp(text: String(localized: "ПРОПУСК"), angle: 14, progress: max(-swipeProgress, 0), isLike: false)
            }
            .padding(.horizontal, 22)
            .padding(.top, 44)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    /// «Душанбе · 3 км · Врач».
    private var subtitle: String {
        let profession = card.profile.profession.flatMap { $0.isEmpty ? nil : $0 }
        return [card.profile.locationLine(catalog: catalog), profession]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

/// Штамп поверх карточки: проявляется и «впечатывается», пока карточку тянут в его сторону.
private struct SwipeStamp: View {
    let text: String
    let angle: Double
    let progress: CGFloat
    let isLike: Bool

    var body: some View {
        Text(text)
            .font(.display(size: 24, weight: .bold))
            .kerning(1.5)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .foregroundStyle(isLike ? AnyShapeStyle(DatingStyle.brandGradient) : AnyShapeStyle(Color.white))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isLike ? AnyShapeStyle(DatingStyle.brandGradient) : AnyShapeStyle(Color.white), lineWidth: 4)
            }
            .background(.black.opacity(isLike ? 0 : 0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotationEffect(.degrees(angle))
            .scaleEffect(1.3 - 0.3 * progress)
            .opacity(Double(progress))
    }
}

/// Заглушка на время загрузки ленты — повторяет форму карточки, чтобы экран не «прыгал».
private struct SkeletonCard: View {
    var body: some View {
        RoundedRectangle(cornerRadius: DatingStyle.cardCornerRadius, style: .continuous)
            .fill(Color.secondary.opacity(0.12))
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 10) {
                    bar(width: 180, height: 26)
                    bar(width: 120, height: 14)
                    HStack(spacing: 6) {
                        bar(width: 70, height: 24)
                        bar(width: 90, height: 24)
                        bar(width: 60, height: 24)
                    }
                }
                .padding(20)
            }
            .shimmering()
            .clipShape(RoundedRectangle(cornerRadius: DatingStyle.cardCornerRadius, style: .continuous))
            .accessibilityLabel("Загружаем анкеты")
    }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        Capsule()
            .fill(Color.secondary.opacity(0.18))
            .frame(width: width, height: height)
    }
}

/// Анкеты на сегодня закончились: вместо тупика — что можно сделать дальше.
private struct EmptyFeedView: View {
    let criteriaLine: String?
    let matchingCount: Int?
    let rouletteOnline: Int?
    let canUndo: Bool
    let onExpandCriteria: () -> Void
    let onOpenSearch: () -> Void
    let onOpenRoulette: () -> Void
    let onUndo: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "heart")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(DatingStyle.rose)
                    .frame(width: 96, height: 96)
                    .background(Color.appSurface, in: Circle())
                    .padding(.top, 32)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                Text("Вы посмотрели всех на сегодня")
                    .font(.display(size: 26, weight: .bold))
                    .multilineTextAlignment(.center)
                Text(summary)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)

                row(
                    systemImage: "person.2", tint: .champagne,
                    title: String(localized: "Расширить «Кого ищу»"),
                    subtitle: criteriaLine ?? String(localized: "Возраст, город, семейное положение"),
                    action: onExpandCriteria
                )
                row(
                    systemImage: "magnifyingglass", tint: .brand,
                    title: String(localized: "Искать самим во вкладке «Поиск»"),
                    subtitle: String(localized: "Все анкеты и свои фильтры"),
                    action: onOpenSearch
                )
                row(
                    systemImage: "shuffle", tint: .brand,
                    title: String(localized: "Попробовать рулетку"),
                    subtitle: rouletteSubtitle,
                    action: onOpenRoulette
                )

                if canUndo {
                    Button("Вернуть последнюю анкету", systemImage: "arrow.uturn.backward", action: onUndo)
                        .font(.app(.callout, weight: .semibold))
                        .foregroundStyle(Color.champagne)
                        .padding(.top, 8)
                }
                Button("Обновить ленту", systemImage: "arrow.clockwise", action: onRefresh)
                    .font(.app(.callout, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var summary: String {
        guard let matchingCount, matchingCount > 0 else {
            return String(localized: "Новые анкеты появляются каждый день. А пока можно расширить поиск или познакомиться по-другому.")
        }
        let people = LikedMeChip.peopleCount(matchingCount)
        return LikedMeChip.takesSingularVerb(matchingCount)
            ? String(localized: "Сейчас вам подходит \(people), и вы его уже видели. Новые анкеты появляются каждый день.")
            : String(localized: "Сейчас вам подходят \(people), и всех вы уже видели. Новые анкеты появляются каждый день.")
    }

    /// Пустая рулетка не зовёт: цифру показываем, только когда там кто-то есть.
    private var rouletteSubtitle: String {
        guard let rouletteOnline, rouletteOnline > 0 else { return String(localized: "Случайный собеседник прямо сейчас") }
        return String(localized: "Сейчас онлайн \(LikedMeChip.peopleCount(rouletteOnline))")
    }

    private func row(systemImage: String, tint: Color, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.app(.body, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Круглая кнопка ленты с подписью под ней.
private struct FeedAction<Control: View>: View {
    let title: String
    @ViewBuilder let button: Control

    var body: some View {
        VStack(spacing: 6) {
            button
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .accessibilityHidden(true)
        }
        .frame(minWidth: 72)
    }
}

/// «Как работает „Написать“» — перед первым сообщением незнакомому человеку.
/// Сроки и правила те же, что у сервера: сообщение живёт сутки, повторно — через 7 дней, без контактов.
private struct IntroExplainerSheet: View {
    let name: String
    let limits: DailyLimits?
    let onConfirm: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "paperplane")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.champagne)
                        .frame(width: 52, height: 52)
                        .background(Color.champagneSoft, in: Circle())
                    Text("Как работает «Написать»")
                        .font(.display(size: 24, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                step(1, title: String(localized: "Сообщение придёт вместе с лайком"),
                     text: String(localized: "\(name) увидит его в «Чатах» → «Вам написали»."))
                step(2, title: String(localized: "Ответит — и вы пара"),
                     text: String(localized: "Откроется обычный чат во вкладке «Чаты»."))
                step(3, title: String(localized: "Не ответит за сутки — сообщение исчезнет"),
                     text: String(localized: "Об отказе вы не узнаете. Написать снова можно через 7 дней."))

                Label {
                    Text("Без ссылок, телефонов и контактов в других мессенджерах — такие сообщения не уйдут.")
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "shield")
                        .foregroundStyle(Color.brand)
                }
                .font(.app(.subheadline))
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let limits {
                    Text(limits.introsLeftText)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 12)
        }
        .safeAreaInset(edge: .bottom) {
            Button("Понятно, написать", action: onConfirm)
                .buttonStyle(.appPrimary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .presentationDetents([.fraction(0.8), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.appSurface)
    }

    private func step(_ number: Int, title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.app(.callout, weight: .bold))
                .foregroundStyle(Color.champagne)
                .frame(width: 30, height: 30)
                .background(Color.champagneSoft, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(.body, weight: .semibold))
                Text(text)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension DailyLimits {
    /// «Сегодня можно написать ещё 4 раза. Новые — в полночь.»
    var introsLeftText: String {
        guard introsLeft > 0 else {
            return String(localized: "Сегодня сообщения закончились — новые появятся в полночь.")
        }
        let lastTwo = introsLeft % 100
        let last = introsLeft % 10
        if (2...4).contains(last) && !(12...14).contains(lastTwo) {
            return String(localized: "Сегодня можно написать ещё \(introsLeft) раза. Новые — в полночь.")
        }
        return String(localized: "Сегодня можно написать ещё \(introsLeft) раз. Новые — в полночь.")
    }
}

/// Поздравление при взаимном лайке — отсюда можно сразу написать в чат пары.
struct MatchCelebrationView: View {
    let match: DatingMatch
    var myPhotoId: String?
    let onClose: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(rgb: 0xB42A4C), Color(rgb: 0x120E12)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            FloatingHeartsView(count: 22, colors: [.white, Color(rgb: 0xF0C27B), Color(rgb: 0xE2455F)])
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                VStack(spacing: 8) {
                    Text("Это взаимно!")
                        .font(.display(size: 34, weight: .bold))
                    Text("Вы и \(match.partner.displayName) понравились друг другу")
                        .font(.app(.headline))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .scaleEffect(appeared ? 1 : 0.6)
                .opacity(appeared ? 1 : 0)

                photos

                Text("\(match.partner.displayName), \(match.partner.age)")
                    .font(.app(.title3, weight: .semibold))
                    .foregroundStyle(.white)
                    .opacity(appeared ? 1 : 0)
                Spacer()
                buttons
                    .offset(y: appeared ? 0 : 80)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(24)
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.1)) { appeared = true }
        }
        .sensoryFeedback(.success, trigger: appeared) { _, isShown in isShown }
    }

    private var photos: some View {
        ZStack {
            photo(myPhotoId)
                .rotationEffect(.degrees(-8))
                .offset(x: appeared ? -64 : -320, y: 8)
            photo(match.partner.photoId)
                .rotationEffect(.degrees(8))
                .offset(x: appeared ? 64 : 320, y: -8)
            Image(systemName: "heart.fill")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(DatingStyle.brandGradient)
                .frame(width: 68, height: 68)
                .background(.white, in: Circle())
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .phaseAnimator([1.0, 1.15]) { content, scale in
                    content.scaleEffect(scale)
                } animation: { _ in
                    .easeInOut(duration: 0.55)
                }
                .scaleEffect(appeared ? 1 : 0.1)
                .offset(y: 110)
        }
        .frame(height: 280)
    }

    private func photo(_ attachmentId: String?) -> some View {
        DatingPhotoView(attachmentId: attachmentId, cornerRadius: 24)
            .frame(width: 150, height: 210)
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white, lineWidth: 4)
            }
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if let chatId = match.chatId {
                Button {
                    // Чат пары открывает вкладка «Чаты» — тем же путём, что и переход из push.
                    PushManager.shared.pendingChatId = chatId
                    onClose()
                } label: {
                    Label("Написать", systemImage: "paperplane.fill")
                        .font(.app(.headline))
                        .foregroundStyle(DatingStyle.rose)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: Capsule())
                }
                .buttonStyle(PressableButtonStyle())
            }
            Button(action: onClose) {
                Text("Продолжить знакомиться")
                    .font(.app(.headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.6), lineWidth: 1.5))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }
}
