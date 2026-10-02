import SwiftUI

/// Вкладка «Рулетка» (макеты «Рулетка — видео и переписка»). Пока человек в рулетке, панель вкладок спрятана:
/// разговор занимает весь экран, а выйти можно только «Стопом».
struct RouletteTabView: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var roulette: RouletteViewModel
    /// «Кого ищу» меняется в «Моём профиле».
    let onEditSearch: () -> Void

    var body: some View {
        DatingGate(dating: dating, title: String(localized: "Рулетка")) {
            RouletteScreen(dating: dating, roulette: roulette, onEditSearch: onEditSearch)
        }
    }
}

private struct RouletteScreen: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var roulette: RouletteViewModel
    let onEditSearch: () -> Void

    var body: some View {
        content
            // Внутри NavigationStack: снаружи него панель вкладок этот модификатор не видит.
            .toolbar(roulette.isInRoulette ? .hidden : .automatic, for: .navigationBar, .tabBar)
            .animation(.easeInOut(duration: 0.25), value: roulette.phase)
            // Жалоба — над всем экраном: если собеседник уйдёт, пока её пишут, экран сменится, а жалоба останется.
            .sheet(item: $roulette.reportTarget, onDismiss: { roulette.resumeAutoSearch() }) { session in
                RouletteReportSheet(roulette: roulette, session: session)
            }
            .alert("Рулетка", isPresented: .constant(roulette.errorMessage != nil)) {
                Button("Ок") { roulette.errorMessage = nil }
            } message: {
                Text(roulette.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var content: some View {
        let places = RoulettePlaces(catalog: dating.catalog, countryCode: dating.profile?.shared.countryCode)
        switch roulette.phase {
        case .idle:
            RouletteStartView(dating: dating, roulette: roulette, places: places, onEditSearch: onEditSearch)
        case .searching(let mode):
            RouletteSearchView(roulette: roulette, mode: mode, places: places)
        case .talking(let session) where session.mode == .video:
            RouletteVideoView(roulette: roulette, engine: roulette.video, session: session, places: places)
        case .talking(let session):
            RouletteTextChatView(roulette: roulette, session: session, places: places)
                // Новый собеседник — новый экран: черновик и подсказки прошлого разговора ему не достаются.
                .id(session.id)
        case .ended(let session, let reported, let autoSearchAt):
            RouletteEndedView(roulette: roulette, session: session, reported: reported, autoSearchAt: autoSearchAt, places: places)
        case .matched(let session, let match):
            RouletteMatchView(roulette: roulette, dating: dating, session: session, match: match, places: places)
        }
    }
}

/// Названия городов из справочника. Собеседник всегда из моей страны — сервер сводит только внутри неё.
struct RoulettePlaces {
    let catalog: DatingCatalog?
    let countryCode: String?

    func city(_ code: String) -> String {
        guard let catalog, let countryCode else { return code }
        return catalog.cityName(countryCode: countryCode, cityCode: code)
    }

    var country: String {
        guard let countryCode else { return "" }
        return catalog?.countries.first { $0.code == countryCode }?.name ?? countryCode
    }

    /// «Девушка, 24 · Душанбе».
    func peerLine(_ peer: RoulettePeer) -> String {
        "\(peer.title) · \(city(peer.cityCode))"
    }
}

// MARK: - Выбор режима

private struct RouletteStartView: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var roulette: RouletteViewModel
    let places: RoulettePlaces
    let onEditSearch: () -> Void

    @State private var showVideoLocked = false
    @State private var showSelfie = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Случайный собеседник. Имя и анкета откроются, только если симпатия взаимна.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                videoCard
                textCard
                if let search = roulette.status?.search {
                    searchRow(search)
                }
                if let evening = roulette.status?.evening {
                    reminderRow(evening)
                }
                if let issue = blockingIssue {
                    Label(issueText(issue), systemImage: "exclamationmark.circle")
                        .font(.app(.footnote, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await roulette.start(roulette.selectedMode) }
                } label: {
                    Label(roulette.selectedMode == .video ? String(localized: "Начать видео") : String(localized: "Начать переписку"), systemImage: "shuffle")
                }
                .buttonStyle(.appPrimary)
                .disabled(roulette.status == nil || blockingIssue != nil)
            }
            .padding(.horizontal, AppMetrics.screenPadding)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .refreshable { await roulette.loadStatus() }
        .task { await roulette.loadStatus() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RouletteViewModel.onlineRefreshInterval))
                await roulette.refreshOnline()
            }
        }
        .toolbar {
            if let online = roulette.status?.online {
                ToolbarItem(placement: .topBarTrailing) {
                    RouletteOnlineBadge(count: online.total, label: String(localized: "сейчас здесь"))
                }
            }
        }
        .sheet(isPresented: $showVideoLocked) {
            RouletteVideoLockedSheet(
                onSelfie: {
                    showVideoLocked = false
                    showSelfie = true
                },
                onText: {
                    showVideoLocked = false
                    Task { await roulette.start(.text) }
                }
            )
            .presentationDetents([.medium])
            .presentationBackground(Color.appSurface)
        }
        .sheet(isPresented: $showSelfie, onDismiss: { Task { await roulette.loadStatus() } }) {
            NavigationStack { SelfieVerificationView(dating: dating) }
        }
    }

    /// Почему выбранный режим не запустить. Нет проверки селфи у видео — не здесь, а окном при выборе.
    private var blockingIssue: RouletteIssue? {
        guard let availability = roulette.status?.availability(of: roulette.selectedMode), !availability.available else { return nil }
        return availability.reason ?? .unknown
    }

    private func issueText(_ issue: RouletteIssue) -> String {
        guard issue == .rouletteBanned, let until = roulette.status?.bannedUntil else { return issue.message }
        return String(localized: "Рулетка закрыта для вас из-за жалоб до \(until.formatted(date: .long, time: .shortened))")
    }

    private var videoLocked: Bool {
        roulette.status?.modes.video.reason == .notVerified
    }

    private var videoCard: some View {
        let selected = roulette.selectedMode == .video
        return Button {
            if videoLocked {
                showVideoLocked = true
            } else {
                roulette.selectedMode = .video
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: "video.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 16)
                Text("Видео")
                    .font(.display(size: 24))
                Group {
                    if let online = roulette.status?.online {
                        Text("Живой разговор лицом к лицу · ") + Text("\(online.video) онлайн").bold()
                    } else {
                        Text("Живой разговор лицом к лицу")
                    }
                }
                .font(.app(.subheadline))
                .opacity(0.9)
                .padding(.top, 6)
                Group {
                    if videoLocked {
                        Label("Нужна проверка селфи", systemImage: "lock.fill")
                    } else {
                        Label { Text("Только проверенные анкеты") } icon: { VerifiedBadge() }
                    }
                }
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(Color.champagne)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.25), in: Capsule())
                .padding(.top, 10)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 206, alignment: .leading)
            .padding(20)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.brandFill)
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(RadialGradient(colors: [Color.champagne.opacity(0.18), .clear], center: .topTrailing, startRadius: 0, endRadius: 200))
            }
            .overlay(alignment: .topTrailing) { if selected { SelectedMark().padding(16) } }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(selected ? Color.champagne : .clear, lineWidth: 2)
            }
            .shadow(color: Color.brand.opacity(0.28), radius: 17, y: 14)
            .opacity(videoLocked ? 0.92 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var textCard: some View {
        let selected = roulette.selectedMode == .text
        return Button {
            roulette.selectedMode = .text
        } label: {
            HStack(spacing: 16) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(width: 52, height: 52)
                    .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Переписка")
                        .font(.display(size: 20))
                        .foregroundStyle(.primary)
                    Text(textCardSubtitle)
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 148)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(alignment: .topTrailing) { if selected { SelectedMark().padding(16) } }
            .overlay {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(selected ? Color.champagne : Color.appLine, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var textCardSubtitle: String {
        guard let online = roulette.status?.online else { return String(localized: "Анонимный текстовый чат. Без фото и ссылок — только слова.") }
        return String(localized: "Анонимный чат, только слова · \(online.text) онлайн")
    }

    /// «Вечер рулетки · 20:00–23:00» с переключателем напоминания (макет «Онлайн и вечер рулетки»).
    private func reminderRow(_ evening: RouletteStatus.Evening) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.champagne)
            VStack(alignment: .leading, spacing: 2) {
                Text("Вечер рулетки · \(evening.range)")
                    .font(.app(.subheadline, weight: .semibold))
                Text("Напомним, когда людей больше всего")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle("Напомнить", isOn: Binding(
                get: { roulette.status?.reminder ?? false },
                set: { roulette.setReminder($0) }
            ))
            .labelsHidden()
            .tint(Color.brand)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: 64)
        .background(Color.champagne.opacity(0.08), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.champagne.opacity(0.28), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func searchRow(_ search: RouletteStatus.Search) -> some View {
        Button(action: onEditSearch) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Кого ищу")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                    Text("\(search.lookingFor == "FEMALE" ? String(localized: "Девушки") : String(localized: "Парни")) · \(search.ageMin)–\(search.ageMax) · \(String(localized: "сначала")) \(places.city(search.cityCode))")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 58)
            .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Золотая галочка выбранного режима.
private struct SelectedMark: View {
    var body: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Color.appBackground)
            .frame(width: 26, height: 26)
            .background(Color.champagne, in: Circle())
            .accessibilityHidden(true)
    }
}

private struct RouletteVideoLockedSheet: View {
    let onSelfie: () -> Void
    let onText: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VerifiedBadge()
                .font(.system(size: 38))
                .frame(width: 72, height: 72)
                .background(Color.champagneSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.champagne.opacity(0.35), lineWidth: 1))
            Text("Видео — только для проверенных")
                .font(.display(size: 20))
                .multilineTextAlignment(.center)
            Text("Так в видео не попадают фейки и случайные люди. Сделайте селфи с камеры — модератор проверит его в течение 24 часов.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onSelfie) {
                Label("Пройти проверку селфи", systemImage: "camera.fill")
            }
            .buttonStyle(.appPrimary)
            .padding(.top, 8)
            Button(action: onText) {
                Label("Пока начать переписку", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.appSecondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }
}

// MARK: - Поиск

private struct RouletteSearchView: View {
    @ObservedObject var roulette: RouletteViewModel
    let mode: RouletteMode
    let places: RoulettePlaces

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Label(mode == .video ? String(localized: "Видео") : String(localized: "Переписка"), systemImage: mode == .video ? "video.fill" : "bubble.left.fill")
                    .font(.app(.subheadline, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.appSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
                if let online = roulette.status?.online {
                    RouletteOnlineBadge(
                        count: online.count(of: mode),
                        label: mode == .video ? String(localized: "в видео") : String(localized: "в переписке")
                    )
                }
            }
            .padding(.top, 22)

            Spacer(minLength: 24)
            ZStack {
                PulseRings()
                    .frame(width: 140, height: 140)
                Image(systemName: "shuffle")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 140, height: 140)
                    .background(.brandFill, in: Circle())
                    .shadow(color: Color.brand.opacity(0.35), radius: 20, y: 18)
            }
            .frame(height: 240)
            Text(title)
                .font(.display(size: 22))
                .padding(.top, 16)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                details(now: context.date)
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)

            if let notice = roulette.notice {
                Text(notice)
                    .font(.app(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
            }
            Spacer(minLength: 24)

            if let evening = roulette.status?.evening {
                Text("Больше всего людей в рулетке с \(evening.range.replacingOccurrences(of: "–", with: " до "))")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 30)
                    .padding(.bottom, 16)
            }
            Button("Отменить") { roulette.stop() }
                .buttonStyle(.appSecondary)
                .frame(width: 200)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                AppBackground()
                RadialGradient(colors: [Color.brand.opacity(0.28), .clear], center: UnitPoint(x: 0.5, y: 0.34), startRadius: 0, endRadius: 260)
                    .ignoresSafeArea()
            }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RouletteViewModel.onlineRefreshInterval))
                await roulette.refreshOnline()
            }
        }
    }

    private var lookingForFemale: Bool { roulette.status?.search?.lookingFor == "FEMALE" }

    private var title: String {
        lookingForFemale ? String(localized: "Ищем собеседницу…") : String(localized: "Ищем собеседника…")
    }

    /// «девушки 21–31» — по кому сервер ищет сейчас (после «Расширить» — шире).
    private var whom: String? {
        guard let ages = roulette.searchAges else { return nil }
        let who = lookingForFemale ? String(localized: "девушки") : String(localized: "парни")
        return "\(who) \(ages.lowerBound)–\(ages.upperBound)"
    }

    /// Первые секунды — шаги «свой город → вся страна»; долго никого — предложение расширить; расширили — итог.
    @ViewBuilder
    private func details(now: Date) -> some View {
        let elapsed = now.timeIntervalSince(roulette.searchStartedAt)
        VStack(spacing: 16) {
            Text(summary(elapsed: elapsed))
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .monospacedDigit()
            if roulette.searchExpanded {
                expandedNote
            } else if elapsed >= RouletteViewModel.expandOfferAfter, let ages = roulette.expandedAges {
                expandCard(ages: ages)
            } else {
                steps(now: now)
            }
        }
    }

    private func summary(elapsed: TimeInterval) -> String {
        let seconds = Int(elapsed)
        let time = String(format: "%d:%02d", seconds / 60, seconds % 60)
        var parts = [String(localized: "Ищем уже \(time)")]
        if let whom { parts.append(whom) }
        if roulette.searchExpanded || seconds >= roulette.cityWaitSeconds { parts.append(String(localized: "весь \(places.country)")) }
        return parts.joined(separator: " · ")
    }

    /// Макет «Долгий поиск — расширить возраст».
    private func expandCard(ages: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "clock")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.champagne)
                    .frame(width: 40, height: 40)
                    .background(Color.champagne.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Подходящих пока нет")
                        .font(.app(.callout, weight: .semibold))
                    Text("Сейчас в рулетке мало людей подходящего возраста. Расширим диапазон на 5 лет в обе стороны — только для этого поиска.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                roulette.expandSearch()
            } label: {
                Label(String(localized: "Расширить: \(ages.lowerBound)–\(ages.upperBound) лет"), systemImage: "arrow.left.and.right")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.champagne)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(Color.appElevated, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.champagne.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }

    private var expandedNote: some View {
        Label("Поиск расширен — по всей стране и шире по возрасту", systemImage: "arrow.left.and.right")
            .font(.app(.footnote, weight: .medium))
            .foregroundStyle(Color.champagne)
            .multilineTextAlignment(.center)
    }

    /// Сначала свой город, через cityWaitSeconds — вся страна (так подбирает сервер).
    private func steps(now: Date) -> some View {
        let left = max(0, roulette.cityWaitSeconds - Int(now.timeIntervalSince(roulette.searchStartedAt)))
        let city = roulette.status?.search.map { places.city($0.cityCode) } ?? ""
        return VStack(spacing: 12) {
            stepRow(title: String(localized: "Рядом — в \(city)"), trailing: left > 0 ? String(localized: "ищем") : "", active: left > 0)
            stepRow(
                title: String(localized: "Затем — весь \(places.country)"),
                trailing: left > 0 ? String(localized: "через \(left) с") : String(localized: "ищем"),
                active: left == 0
            )
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }

    private func stepRow(title: String, trailing: String, active: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(active ? Color.brand : .clear)
                .overlay(Circle().strokeBorder(active ? .clear : Color.secondary.opacity(0.6), lineWidth: 1.5))
                .frame(width: 10, height: 10)
                .shadow(color: active ? Color.brand.opacity(0.5) : .clear, radius: 4)
            Text(title)
                .font(.app(.subheadline, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? .primary : .secondary)
            Spacer()
            Text(trailing)
                .font(.app(.caption, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color.brand : .secondary)
                .monospacedDigit()
        }
    }
}

// MARK: - Собеседник ушёл

private struct RouletteEndedView: View {
    @ObservedObject var roulette: RouletteViewModel
    let session: RouletteViewModel.Session
    let reported: Bool
    let autoSearchAt: Date
    let places: RoulettePlaces

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 14) {
                Image(systemName: reported ? "flag.fill" : "person.crop.circle.badge.xmark")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 96, height: 96)
                    .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
                Text(title)
                    .font(.display(size: 22))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                Text(subtitle)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            VStack(spacing: 16) {
                if canLike || roulette.liked && !reported {
                    likeRow
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(left: max(0, Int(autoSearchAt.timeIntervalSince(context.date).rounded(.up))))
                }
            }
            .padding(.top, 40)
            .padding(.horizontal, 20)
            Spacer()

            VStack(spacing: 10) {
                Button {
                    roulette.next()
                } label: {
                    Label("Искать сейчас", systemImage: "shuffle")
                }
                .buttonStyle(.appPrimary)
                Button("Выйти из рулетки") { roulette.stop() }
                    .buttonStyle(.appSecondary)
                if !reported {
                    Button {
                        roulette.beginReport()
                    } label: {
                        Label(session.peer.isFemale ? String(localized: "Пожаловаться на собеседницу") : String(localized: "Пожаловаться на собеседника"), systemImage: "flag")
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(AppBackground())
    }

    /// Экран открыли сразу после разговора: «Нравится» доступно, пока он на экране (5 минут на сервере с запасом).
    private var canLike: Bool { roulette.canLikeAfterEnd }

    /// Макеты «Нравится после разговора» и «Отметка отправлена».
    @ViewBuilder
    private var likeRow: some View {
        if roulette.liked {
            HStack(spacing: 14) {
                Image(systemName: "checkmark")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(Color.appBackground)
                    .frame(width: 40, height: 40)
                    .background(Color.champagne, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Вы отметили «Нравится»")
                        .font(.app(.callout, weight: .bold))
                        .foregroundStyle(Color.champagne)
                    Text(session.peer.isFemale ? String(localized: "Если она тоже — пара появится в «Чатах»") : String(localized: "Если он тоже — пара появится в «Чатах»"))
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .frame(minHeight: 64)
            .background(Color.champagne.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.champagne.opacity(0.4), lineWidth: 1))
            .accessibilityElement(children: .combine)
        } else {
            Button {
                roulette.like()
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.brandFill, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Нравится")
                            .font(.app(.callout, weight: .bold))
                            .foregroundStyle(.primary)
                        Text(String(localized: "Можно отметить ещё 5 минут · \(session.peer.age), \(places.city(session.peer.cityCode))"))
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .frame(minHeight: 64)
                .background(Color.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.brand.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    private var title: String {
        if reported { return String(localized: "Жалоба отправлена") }
        return session.peer.isFemale ? String(localized: "Собеседница завершила разговор") : String(localized: "Собеседник завершил разговор")
    }

    private var subtitle: String {
        if reported { return String(localized: "Модератор проверит её. Вы больше не встретитесь в рулетке.") }
        if canLike || roulette.liked {
            return session.peer.isFemale
                ? String(localized: "Связь могла прерваться случайно. Понравилась — отметьте: если она тоже, появится пара.")
                : String(localized: "Связь могла прерваться случайно. Понравился — отметьте: если он тоже, появится пара.")
        }
        if session.mode == .text { return String(localized: "Переписка исчезла у вас обоих. Ничего страшного — следующий человек уже ищется.") }
        return String(localized: "Ничего страшного — следующий человек уже ищется.")
    }

    private func countdown(left: Int) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.appElevated, lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(left) / CGFloat(RouletteViewModel.autoSearchDelay))
                    .stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: left)
                Text("\(left)")
                    .font(.display(size: 18))
                    .monospacedDigit()
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.peer.isFemale ? String(localized: "Следующая собеседница") : String(localized: "Следующий собеседник"))
                    .font(.app(.callout, weight: .semibold))
                Text(left > 0 ? String(localized: "Поиск начнётся через \(left) с") : String(localized: "Начинаем поиск…"))
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .appCard(cornerRadius: 22)
    }
}

// MARK: - Жалоба

struct RouletteReportSheet: View {
    @ObservedObject var roulette: RouletteViewModel
    let session: RouletteViewModel.Session

    @Environment(\.dismiss) private var dismiss
    @State private var reason = RouletteReportReason.indecent
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Пожаловаться")
                .font(.display(size: 20))
                .padding(.top, 24)
            Text(session.peer.isFemale
                ? String(localized: "Разговор сразу завершится, и вы больше не встретитесь в рулетке. Собеседница не узнает, кто пожаловался.")
                : String(localized: "Разговор сразу завершится, и вы больше не встретитесь в рулетке. Собеседник не узнает, кто пожаловался."))
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
            ForEach(RouletteReportReason.allCases) { item in
                let selected = item == reason
                Button {
                    reason = item
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 20))
                            .foregroundStyle(selected ? Color.brand : .secondary)
                        Text(item.title)
                            .font(.app(.callout, weight: selected ? .semibold : .regular))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .frame(minHeight: 50)
                    .background(selected ? Color.brandSoft : Color.appElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? Color.brand : Color.appLine, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            Button {
                isSending = true
                Task {
                    let sent = await roulette.report(session, reason: reason, comment: nil)
                    isSending = false
                    if sent { dismiss() }
                }
            } label: {
                if isSending { ProgressView().tint(.white) } else { Text("Отправить и завершить") }
            }
            .buttonStyle(.appPrimary)
            .disabled(isSending)
            .padding(.top, 6)
            Button("Отмена") { dismiss() }
                .buttonStyle(.appQuiet)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.large])
        .presentationBackground(Color.appSurface)
    }
}

// MARK: - Симпатия взаимна

private struct RouletteMatchView: View {
    @ObservedObject var roulette: RouletteViewModel
    @ObservedObject var dating: DatingViewModel
    let session: RouletteViewModel.Session
    let match: DatingMatch?
    let places: RoulettePlaces

    @State private var profile: DatingProfilePublic?
    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            RadialGradient(colors: [Color(rgb: 0xB42A4C).opacity(0.85), .clear], center: UnitPoint(x: 0.3, y: 0.2), startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
            RadialGradient(colors: [Color(rgb: 0x5A1733).opacity(0.9), .clear], center: UnitPoint(x: 0.8, y: 0.75), startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
            FloatingHeartsView(count: 14, colors: [.white, Color(rgb: 0xF0C27B), Color(rgb: 0xE2455F)])
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                photos
                    .scaleEffect(appeared ? 1 : 0.7)
                    .opacity(appeared ? 1 : 0)
                details
                    .padding(.top, 36)
                Spacer()
                buttons
                    .offset(y: appeared ? 0 : 60)
                    .opacity(appeared ? 1 : 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .foregroundStyle(.white)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.1)) { appeared = true }
        }
        .sensoryFeedback(.success, trigger: appeared) { _, shown in shown }
        .sheet(item: $profile) { profile in
            NavigationStack {
                DatingProfileDetailView(profile: profile, catalog: dating.catalog)
            }
        }
    }

    private var photos: some View {
        HStack(spacing: -22) {
            photo(dating.profile?.shared.photoIds.first)
                .rotationEffect(.degrees(-6))
            Image(systemName: "heart.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.brandFill, in: Circle())
                .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 4))
                .zIndex(1)
            photo(match?.partner.photoId)
                .rotationEffect(.degrees(6))
        }
    }

    private func photo(_ attachmentId: String?) -> some View {
        DatingPhotoView(attachmentId: attachmentId, cornerRadius: 59)
            .frame(width: 118, height: 118)
            .clipShape(Circle())
            .padding(4)
            .background(Color.appBackground, in: Circle())
            .overlay(Circle().strokeBorder(Color.champagne, lineWidth: 3))
    }

    private var details: some View {
        VStack(spacing: 10) {
            Text("Симпатия взаимна")
                .textCase(.uppercase)
                .font(.app(.footnote, weight: .bold))
                .tracking(1.4)
                .foregroundStyle(Color.champagne)
            if let match {
                HStack(spacing: 8) {
                    Text("\(match.partner.displayName), \(match.partner.age)")
                        .font(.display(size: 30))
                    if session.peer.verified { VerifiedBadge().font(.system(size: 22)) }
                }
                .multilineTextAlignment(.center)
                Label(places.city(match.partner.cityCode), systemImage: "mappin")
                    .font(.app(.subheadline))
                    .opacity(0.8)
            } else {
                ProgressView().tint(.white).frame(height: 36)
            }
            Text(session.mode == .text
                ? String(localized: "Теперь вы пара. Ваша переписка из рулетки сохранена в «Чатах» — продолжайте с того же места.")
                : String(localized: "Теперь вы пара. Чат уже ждёт в «Чатах» — напишите первым."))
                .font(.app(.subheadline))
                .opacity(0.78)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                // Чат пары открывает вкладка «Чаты» — тем же путём, что и переход из push.
                PushManager.shared.pendingChatId = match?.chatId
                roulette.closeMatch()
            } label: {
                Label("Открыть чат", systemImage: "bubble.left.fill")
                    .font(.app(.body, weight: .bold))
                    .foregroundStyle(Color.appBackground)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(match?.chatId == nil)

            Button {
                guard let userId = match?.partner.userId else { return }
                Task {
                    do {
                        profile = try await APIClient.shared.fetchDatingProfile(userId: userId)
                    } catch {
                        roulette.errorMessage = error.localizedDescription
                    }
                }
            } label: {
                Label("Посмотреть анкету", systemImage: "person.text.rectangle")
                    .font(.app(.body, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Color.black.opacity(0.35), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(match == nil)

            Button("Продолжить рулетку") {
                Task { await roulette.start(session.mode) }
            }
            .font(.app(.callout, weight: .semibold))
            .foregroundStyle(.white.opacity(0.8))
            .padding(10)
        }
    }
}

/// Зелёная плашка «● 14 сейчас здесь» — сколько людей в рулетке.
struct RouletteOnlineBadge: View {
    let count: Int
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(Color.rouletteOnline)
                .frame(width: 8, height: 8)
                .background(Circle().fill(Color.rouletteOnline.opacity(0.25)).frame(width: 14, height: 14))
            Text("\(count)")
                .font(.app(.footnote, weight: .semibold))
                .foregroundStyle(Color.rouletteOnlineText)
                .monospacedDigit()
            Text(label)
                .font(.app(.footnote, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .background(Color.rouletteOnline.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.rouletteOnline.opacity(0.32), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

private extension Color {
    /// Зелёный «в сети» из макета рулетки.
    static let rouletteOnline = Color(light: 0x2E9A5E, dark: 0x4CAF78)
    static let rouletteOnlineText = Color(light: 0x1F7A47, dark: 0x7FD8A4)
}
