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

/// Лента знакомств: подходящие анкеты стопкой, оценка кнопками или жестом, дневные лимиты.
/// Фильтров здесь нет намеренно — подбор делает сервер; фильтры и поиск по @username — в сетке анкет.
struct DatingFeedView: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var matches: MatchesViewModel

    @StateObject private var feed = DatingFeedViewModel()
    @State private var showProfileEditor = false
    @State private var showMatches = false
    @State private var detailCard: DatingFeedCard?
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

    var body: some View {
        VStack(spacing: 0) {
            if let profile = dating.profile, !profile.visibleToOthers {
                visibilityBanner(profile)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
            content
        }
        .background(DatingBackdrop())
        .safeAreaInset(edge: .bottom) { actionBar }
        .toolbar { toolbarContent }
        .navigationDestination(isPresented: $showMatches) {
            MatchesView(dating: dating, matches: matches)
        }
        .task(id: dating.searchSettingsRevision) { await feed.load() }
        .task(id: visibleCards.first?.id) { prefetchUpcomingPhotos() }
        .sensoryFeedback(.selection, trigger: pastThreshold) { _, isPast in isPast }
        .sheet(isPresented: $showProfileEditor) {
            NavigationStack { DatingProfileEditorView(dating: dating) }
        }
        .sheet(item: $detailCard) { card in
            NavigationStack {
                DatingProfileDetailView(
                    profile: card.profile,
                    catalog: dating.catalog,
                    compatibility: card.compatibility,
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

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                showProfileEditor = true
            } label: {
                DatingPhotoView(attachmentId: dating.profile?.shared.photoIds.first, cornerRadius: 16)
                    .frame(width: 32, height: 32)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Моя анкета")
        }
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                showMatches = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .overlay(alignment: .topTrailing) {
                        if pendingCount > 0 {
                            Text("\(pendingCount)")
                                .font(.app(.caption2, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(DatingStyle.rose, in: Capsule())
                                .offset(x: 9, y: -7)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: pendingCount)
            }
            .accessibilityLabel(pendingCount > 0 ? "Пары и сообщения, новых: \(pendingCount)" : "Пары и сообщения")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let blocked = feed.blockedMessage {
            ContentUnavailableView("Лента закрыта", systemImage: "heart.slash", description: Text(blocked))
        } else if visibleCards.isEmpty {
            if feed.isLoading {
                SkeletonCard()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                EmptyFeedView(photoId: dating.profile?.shared.photoIds.first) {
                    Task { await feed.load() }
                }
            }
        } else {
            cardStack
        }
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
                    DatingCardView(card: card, catalog: dating.catalog, swipeProgress: isTop ? swipeProgress : 0) {
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
                }
            }
            .onAppear { stackWidth = proxy.size.width }
            .onChange(of: proxy.size.width) { _, width in stackWidth = width }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
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

    private var actionBar: some View {
        VStack(spacing: 10) {
            if let card = visibleCards.first {
                HStack(spacing: 22) {
                    DatingActionButton(kind: .skip, size: 62) { send(card, .skip) }
                        .scaleEffect(1 + max(-swipeProgress, 0) * 0.15)
                    DatingActionButton(kind: .intro, size: 50) { PushManager.shared.openConversation(with: card.profile) }
                    DatingActionButton(kind: .like, size: 72) { send(card, .like) }
                        .scaleEffect(1 + max(swipeProgress, 0) * 0.15)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let limits = feed.limits {
                limitsLabel(limits)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .animation(DatingStyle.spring, value: visibleCards.isEmpty)
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

    private var pendingCount: Int {
        matches.incoming.count
    }

    private func limitsText(_ limits: DailyLimits) -> String {
        if limits.likesLeft == 0 {
            return "Лайки закончились — вернутся \(limits.resetsAt.formatted(date: .omitted, time: .shortened))"
        }
        return "Лайков сегодня: \(limits.likesLeft) из \(limits.likesPerDay) · сообщений: \(limits.introsLeft) из \(limits.introsPerDay)"
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

/// Карточка кандидата: фото листаются тапом по краям, снизу — имя, совместимость и главное об анкете.
private struct DatingCardView: View {
    let card: DatingFeedCard
    let catalog: DatingCatalog?
    /// −1…1: насколько карточку утянули влево или вправо — от этого зависят штампы и подсветка.
    let swipeProgress: CGFloat
    let onOpen: () -> Void

    @State private var photoIndex = 0
    @State private var edgeTilt: Double = 0
    @State private var edgeBumps = 0

    private let visibleInterests = 3

    var body: some View {
        ZStack(alignment: .bottom) {
            DatingPhotoView(attachmentId: currentPhotoId, cornerRadius: 0)
                .overlay { photoTapZones }

            scrim
                .allowsHitTesting(false)

            info
        }
        .overlay(alignment: .top) { photoPager }
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
            .padding(.horizontal, 14)
            .padding(.top, 10)
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
            .frame(height: 300)
        }
    }

    private var info: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                badges
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(card.profile.displayName)
                                .font(.display(size: 26, weight: .semibold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("\(card.profile.age)")
                                .font(.display(size: 22, weight: .medium))
                            if card.profile.verified {
                                VerifiedBadge()
                                    .font(.app(.title3))
                            }
                        }
                        Label(subtitle, systemImage: "mappin.and.ellipse")
                            .font(.app(.subheadline, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    CompatibilityRing(score: card.compatibility.score)
                }
                if let reason = card.compatibility.reasons.first {
                    Label(reason, systemImage: "sparkles")
                        .font(.app(.footnote, weight: .semibold))
                        .lineLimit(2)
                }
                chips
                HStack(spacing: 4) {
                    Text("Подробнее")
                    Image(systemName: "chevron.up")
                }
                .font(.app(.caption, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var badges: some View {
        if card.isNew || card.expanded {
            HStack(spacing: 6) {
                if card.isNew {
                    DatingChip(text: "Новенький", systemImage: "sparkle", onPhoto: true)
                }
                if card.expanded {
                    DatingChip(text: "Шире фильтров", systemImage: "arrow.up.left.and.arrow.down.right", onPhoto: true)
                }
            }
        }
    }

    private var chips: some View {
        let goal = catalog?.relationshipGoals.name(of: card.profile.relationshipGoal)
        let interests = catalog?.names(of: card.profile.interests, in: catalog?.interests ?? []) ?? []
        return FlowLayout(spacing: 6) {
            if let goal {
                DatingChip(text: goal, systemImage: "heart", onPhoto: true)
            }
            if let profession = card.profile.profession, !profession.isEmpty {
                DatingChip(text: profession, systemImage: "briefcase", onPhoto: true)
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
                SwipeStamp(text: "НРАВИТСЯ", angle: -14, progress: max(swipeProgress, 0), isLike: true)
                Spacer()
                SwipeStamp(text: "ПРОПУСК", angle: 14, progress: max(-swipeProgress, 0), isLike: false)
            }
            .padding(.horizontal, 22)
            .padding(.top, 44)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .allowsHitTesting(false)
    }

    private var subtitle: String {
        var parts = [catalog?.cityName(countryCode: card.profile.countryCode, cityCode: card.profile.cityCode) ?? card.profile.cityCode]
        if let distance = card.profile.distanceText {
            parts.append(distance)
        }
        return parts.joined(separator: " · ")
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

/// Анкеты закончились: своё фото в центре «радара» — ищем дальше.
private struct EmptyFeedView: View {
    let photoId: String?
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                PulseRings()
                    .frame(width: 120, height: 120)
                DatingPhotoView(attachmentId: photoId, cornerRadius: 60)
                    .frame(width: 120, height: 120)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                    .shadow(color: DatingStyle.rose.opacity(0.35), radius: 16, y: 6)
            }
            .frame(height: 260)
            VStack(spacing: 8) {
                Text("Анкеты закончились")
                    .font(.app(.title2, weight: .bold))
                Text("Загляните позже — каждый день появляются новые люди. А все анкеты с фильтрами — во вкладке «Анкеты».")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Button("Обновить", systemImage: "arrow.clockwise", action: onRefresh)
                .glassProminentButtonStyle()
                .tint(DatingStyle.rose)
                .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
