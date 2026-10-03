import SwiftUI

/// Вкладка «Рулетка» (макеты «Рулетка — видео и переписка»). Пока человек в рулетке, панель вкладок спрятана:
/// разговор занимает весь экран, а выйти можно только «Стопом».
struct RouletteTabView: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var roulette: RouletteViewModel
    /// «Кого ищу» меняется в профиле.
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
            // У главной свой заголовок по макету, у остальных экранов рулетки его нет вовсе.
            .toolbar(.hidden, for: .navigationBar)
            .toolbar(roulette.isInRoulette ? .hidden : .automatic, for: .tabBar)
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

/// Главная рулетки (макеты «Рулетка — вариант А, доработка»): сначала режим, потом большая кнопка в кольцах.
/// Точек на кольцах столько, сколько людей сейчас онлайн в выбранном режиме.
private struct RouletteStartView: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var roulette: RouletteViewModel
    let places: RoulettePlaces
    let onEditSearch: () -> Void

    @State private var showSettings = false
    @State private var showSelfie = false
    /// «Изменить» в листе ведёт в «Кого ищу» профиля — переходим, когда лист уже закрылся.
    @State private var editSearchAfterSettings = false
    @Namespace private var modeNamespace

    var body: some View {
        // Раз в минуту: «Вечер рулетки» начинается и заканчивается, пока экран открыт.
        TimelineView(.everyMinute) { context in
            content(eveningLive: roulette.status?.evening?.isLive(at: context.date) ?? false)
        }
        .background(AppBackground())
        .task { await roulette.loadStatus() }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RouletteViewModel.onlineRefreshInterval))
                await roulette.refreshOnline()
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            guard editSearchAfterSettings else { return }
            editSearchAfterSettings = false
            onEditSearch()
        }) {
            if let search = roulette.status?.search {
                RouletteSearchSettingsSheet(roulette: roulette, search: search, places: places) {
                    editSearchAfterSettings = true
                    showSettings = false
                }
                .presentationDetents([.height(600)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.appSurface)
            }
        }
        .sheet(isPresented: $showSelfie, onDismiss: { Task { await roulette.loadStatus() } }) {
            NavigationStack { SelfieVerificationView(dating: dating) }
        }
    }

    private func content(eveningLive: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                header(eveningLive: eveningLive)
                modePicker
                if showsLocked {
                    RouletteStage(dots: onlineCount, glow: 0.10, goldEvery: 0) { lockedCenter }
                        .padding(.top, 12)
                    lockedCard
                        .padding(.horizontal, 16)
                        .padding(.top, -24)
                } else {
                    RouletteStage(dots: onlineCount, glow: eveningLive ? 0.30 : (isVideo ? 0.22 : 0.16), goldEvery: eveningLive ? 0 : 4) { startButton }
                        .padding(.top, 12)
                    if let online = roulette.status?.online {
                        onlineLine(online.count(of: roulette.selectedMode))
                            .padding(.top, 4)
                    }
                    note
                        .padding(.horizontal, 36)
                        .padding(.top, 10)
                    if let search = roulette.status?.search {
                        settingsCard(search: search, eveningLive: eveningLive)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .refreshable { await roulette.loadStatus() }
    }

    private var isVideo: Bool { roulette.selectedMode == .video }

    private var videoLocked: Bool {
        roulette.status?.modes.video.reason == .notVerified
    }

    /// Видео выбрано, но селфи не подтверждено: вместо кнопки — замок и предложение пройти проверку.
    private var showsLocked: Bool { isVideo && videoLocked }

    private var onlineCount: Int {
        roulette.status?.online?.count(of: roulette.selectedMode) ?? 0
    }

    /// Почему выбранный режим не запустить (кроме проверки селфи у видео — у неё свой экран).
    private var blockingIssue: RouletteIssue? {
        guard let availability = roulette.status?.availability(of: roulette.selectedMode), !availability.available else { return nil }
        return availability.reason ?? .unknown
    }

    private func issueText(_ issue: RouletteIssue) -> String {
        guard issue == .rouletteBanned, let until = roulette.status?.bannedUntil else { return issue.message }
        return String(localized: "Рулетка закрыта для вас из-за жалоб до \(until.formatted(date: .long, time: .shortened))")
    }

    private func header(eveningLive: Bool) -> some View {
        HStack(spacing: 8) {
            Text("Рулетка")
                .font(.display(size: 24))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if eveningLive {
                Label("Вечер рулетки", systemImage: "sparkles")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(Color.champagne)
                    .padding(.leading, 10)
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
                    .background(Color.champagne.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.champagne.opacity(0.35), lineWidth: 1))
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .disabled(roulette.status?.search == nil)
            .accessibilityLabel("Настройки поиска")
        }
        .padding(.leading, 20)
        .padding(.trailing, 16)
        .padding(.top, 6)
        .padding(.bottom, 16)
    }

    // MARK: Режим

    private var modePicker: some View {
        HStack(spacing: 4) {
            modeButton(.video)
            modeButton(.text)
        }
        .padding(4)
        .background(Color.appSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    private func modeButton(_ mode: RouletteMode) -> some View {
        let selected = roulette.selectedMode == mode
        return Button {
            withAnimation(DatingStyle.spring) { roulette.selectedMode = mode }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode == .video ? "video" : "bubble.left")
                    .font(.system(size: 16, weight: .semibold))
                Text(mode == .video ? String(localized: "Видео") : String(localized: "Переписка"))
                    .font(.app(.callout, weight: .semibold))
                if mode == .video && videoLocked {
                    Image(systemName: "lock")
                        .font(.system(size: 12, weight: .bold))
                        .accessibilityLabel("Нужна проверка селфи")
                } else if let online = roulette.status?.online {
                    Text("\(online.count(of: mode))")
                        .font(.app(.caption, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(selected ? Color.black.opacity(0.22) : Color.appElevated, in: Capsule())
                        .accessibilityLabel("\(online.count(of: mode)) онлайн")
                }
            }
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background {
                if selected {
                    Capsule()
                        .fill(.brandFill)
                        .shadow(color: Color.brand.opacity(0.3), radius: 9, y: 8)
                        .matchedGeometryEffect(id: "mode", in: modeNamespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Кнопка и подписи

    private var startButton: some View {
        Button {
            Task { await roulette.start(roulette.selectedMode) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: isVideo ? "video" : "bubble.left")
                    .font(.system(size: 30, weight: .semibold))
                Text("Начать")
                    .font(.app(size: 18, weight: .bold))
                    .padding(.top, 4)
                Text(isVideo ? String(localized: "видео") : String(localized: "переписку"))
                    .font(.app(size: 14, weight: .medium))
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(width: 152, height: 152)
            .background(.brandFill, in: Circle())
            .background(Circle().fill(Color.brand.opacity(0.14)).padding(-10))
            .shadow(color: Color.brand.opacity(0.42), radius: 22, y: 20)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(roulette.status == nil || blockingIssue != nil)
        .opacity(roulette.status == nil || blockingIssue != nil ? 0.5 : 1)
        .accessibilityLabel(isVideo ? String(localized: "Начать видео") : String(localized: "Начать переписку"))
    }

    private func onlineLine(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.rouletteOnline)
                .frame(width: 8, height: 8)
                .background(Circle().fill(Color.rouletteOnline.opacity(0.25)).frame(width: 14, height: 14))
            Text(isVideo
                ? String(localized: "\(LikedMeChip.peopleCount(count)) сейчас в видео")
                : String(localized: "\(LikedMeChip.peopleCount(count)) сейчас в переписке"))
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(Color.rouletteOnlineText)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// Одна строка под кнопкой: что за режим и когда откроется анкета, или почему начать нельзя.
    private var note: some View {
        Group {
            if let issue = blockingIssue {
                Text(Image(systemName: "exclamationmark.circle")) + Text(" ") + Text(issueText(issue))
            } else if isVideo {
                Text(Image(systemName: "checkmark.seal.fill")).foregroundStyle(Color.champagne)
                    + Text(" ") + Text("Только проверенные анкеты.").fontWeight(.semibold).foregroundStyle(Color.champagne)
                    + Text(" ") + Text("Имя и анкета откроются, только если симпатия взаимна.")
            } else {
                Text("Без фото и ссылок — только слова. Имя и анкета откроются, только если симпатия взаимна.")
            }
        }
        .font(.app(.footnote))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: «Ищем» и «Вечер рулетки»

    private func settingsCard(search: RouletteStatus.Search, eveningLive: Bool) -> some View {
        VStack(spacing: 0) {
            Button {
                showSettings = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ищем")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text(searchLine(search))
                            .font(.app(.subheadline, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.leading, 16)
                .padding(.trailing, 14)
                .frame(minHeight: 58)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let evening = roulette.status?.evening {
                Divider()
                    .overlay(Color.appLine)
                    .padding(.leading, 50)
                if eveningLive {
                    eveningLiveRow(evening)
                } else {
                    reminderRow(evening)
                }
            }
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }

    /// «Девушки · 21–31 год · Душанбе».
    private func searchLine(_ search: RouletteStatus.Search) -> String {
        let who = search.lookingFor == "FEMALE" ? String(localized: "Девушки") : String(localized: "Парни")
        return "\(who) · \(search.ageMin)–\(RussianPlural.years(search.ageMax)) · \(places.city(search.cityCode))"
    }

    private func reminderRow(_ evening: RouletteStatus.Evening) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.champagne)
                .frame(width: 22)
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
        .frame(minHeight: 58)
        .accessibilityElement(children: .combine)
    }

    private func eveningLiveRow(_ evening: RouletteStatus.Evening) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Color.champagne)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text("Сейчас вечер рулетки")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.champagne)
                Text("До \(evening.endTime) людей больше всего — самое время")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Color.champagne.opacity(0.1))
        .accessibilityElement(children: .combine)
    }

    // MARK: Видео без проверки селфи

    private var lockedCenter: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock")
                .font(.system(size: 30, weight: .semibold))
            Text("Видео — после\nпроверки")
                .font(.app(size: 15, weight: .semibold))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(width: 152, height: 152)
        .background(Color.appElevated, in: Circle())
        .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private var lockedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label { Text("Видео — только для проверенных") } icon: { VerifiedBadge() }
                .font(.app(.callout, weight: .bold))
            Text("Так в видео не попадают фейки. Сделайте селфи — модератор проверит его в течение 24 часов.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
                .padding(.bottom, 14)
            Button {
                showSelfie = true
            } label: {
                Label("Пройти проверку селфи", systemImage: "camera")
            }
            .buttonStyle(.appPrimary)
            Button {
                withAnimation(DatingStyle.spring) { roulette.selectedMode = .text }
            } label: {
                Text(textInsteadTitle)
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.champagne.opacity(0.3), lineWidth: 1))
    }

    private var textInsteadTitle: String {
        guard let online = roulette.status?.online else { return String(localized: "Пока начать переписку") }
        return String(localized: "Пока начать переписку · \(online.text) онлайн")
    }
}

/// Места точек на кольцах как на макете: радиус кольца, угол в градусах, размер.
private let rouletteDotSpots: [(radius: CGFloat, degrees: Double, size: CGFloat)] = [
    (150, 205, 10), (150, 250, 9), (150, 300, 12), (150, 340, 8), (150, 25, 10), (115, 120, 9),
    (115, 175, 8), (115, 265, 10), (150, 150, 8), (115, 40, 9), (150, 95, 8), (115, 320, 8),
    (150, 125, 7), (115, 80, 7), (150, 60, 9), (115, 220, 7), (150, 175, 7), (115, 0, 8),
]

/// Кольца и точки вокруг главной кнопки. Точка — условный человек онлайн, без лица: в рулетке до симпатии
/// никого не видно. На поиске точки медленно кружат.
private struct RouletteStage<Center: View>: View {
    let dots: Int
    var glow: Double = 0.22
    /// Каждая goldEvery-я точка — золотая; 0 — все фирменного цвета.
    var goldEvery = 4
    var spinning = false
    @ViewBuilder let center: Center

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    @State private var turned = false


    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.brand.opacity(glow), .clear], center: .center, startRadius: 0, endRadius: 200)
                .frame(width: 400, height: 400)
            ring(radius: 150, opacity: 0.16)
                .scaleEffect(pulse ? 1.04 : 1)
                .opacity(pulse ? 0.6 : 1)
            ring(radius: 115, opacity: 0.26)
            ring(radius: 82, opacity: 0.38)
            ZStack {
                ForEach(0..<min(dots, rouletteDotSpots.count), id: \.self) { index in
                    dot(index)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .rotationEffect(.degrees(turned ? 360 : 0))
            .accessibilityHidden(true)
            center
        }
        .frame(width: 330, height: 330)
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.35), value: dots)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) { pulse = true }
            if spinning {
                withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { turned = true }
            }
        }
    }

    private func ring(radius: CGFloat, opacity: Double) -> some View {
        Circle()
            .strokeBorder(Color.brand.opacity(opacity), lineWidth: 1)
            .frame(width: radius * 2, height: radius * 2)
            .accessibilityHidden(true)
    }

    private func dot(_ index: Int) -> some View {
        let spot = rouletteDotSpots[index]
        let color = goldEvery > 0 && index % goldEvery == goldEvery - 1 ? Color.champagne : Color.brand
        let angle = spot.degrees * .pi / 180
        return Circle()
            .fill(color)
            .frame(width: spot.size, height: spot.size)
            .shadow(color: color, radius: 6)
            .offset(x: spot.radius * cos(angle), y: spot.radius * sin(angle))
    }
}

/// Кнопка «Начать» на поиске становится таймером: «0:12 ищем», вокруг бежит дуга.
private struct RouletteSearchTimer: View {
    let mode: RouletteMode
    let elapsed: TimeInterval

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false

    var body: some View {
        let seconds = max(0, Int(elapsed))
        VStack(spacing: 4) {
            Image(systemName: mode == .video ? "video" : "bubble.left")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.brand)
            Text(String(format: "%d:%02d", seconds / 60, seconds % 60))
                .font(.display(size: 26))
                .monospacedDigit()
                .padding(.top, 2)
            Text("ищем")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
        }
        .frame(width: 152, height: 152)
        .background(Color.appSurface, in: Circle())
        .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
        .background(Circle().fill(Color.brand.opacity(0.1)).padding(-10))
        .overlay {
            ZStack {
                Circle().trim(from: 0, to: 0.25).stroke(Color.brand, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle().trim(from: 0.25, to: 0.5).stroke(Color.brand.opacity(0.4), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            .padding(-6)
            .rotationEffect(.degrees(turned ? 360 : 0))
            .accessibilityHidden(true)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { turned = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Ищем уже \(String(format: "%d:%02d", seconds / 60, seconds % 60))"))
    }
}

/// «Кого ищем в рулетке» (макет «Лист „Кого ищем в рулетке“»): пол — из «Кого ищу», возраст — только для рулетки.
private struct RouletteSearchSettingsSheet: View {
    @ObservedObject var roulette: RouletteViewModel
    let search: RouletteStatus.Search
    let places: RoulettePlaces
    let onEditLookingFor: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var ages: ClosedRange<Int>

    init(roulette: RouletteViewModel, search: RouletteStatus.Search, places: RoulettePlaces, onEditLookingFor: @escaping () -> Void) {
        self.roulette = roulette
        self.search = search
        self.places = places
        self.onEditLookingFor = onEditLookingFor
        _ages = State(initialValue: search.ageMin...search.ageMax)
    }

    /// Как на макете — 18–60; если возраст уже задан шире, шкала дотягивается до него.
    private var bounds: ClosedRange<Int> {
        DatingLimits.minAge...max(Self.sliderMaxAge, search.ageMax)
    }

    private static let sliderMaxAge = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Кого ищем в рулетке")
                    .font(.display(size: 20))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color.appElevated, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            .padding(.bottom, 4)

            row(
                systemImage: "person", label: String(localized: "Собеседники"),
                value: search.lookingFor == "FEMALE" ? String(localized: "Девушки") : String(localized: "Парни"),
                note: String(localized: "Как в вашем «Кого ищу». Меняется там же.")
            ) {
                Button("Изменить", action: onEditLookingFor)
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.top, 16)
            }
            divider
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    icon("calendar")
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Возраст собеседника")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                        Text("\(ages.lowerBound)–\(RussianPlural.years(ages.upperBound))")
                            .font(.app(.callout, weight: .semibold))
                            .monospacedDigit()
                    }
                }
                RouletteAgeRangeSlider(range: $ages, bounds: bounds)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                Text("Только для рулетки — в ленте и «Поиске» всё останется как было.")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            divider
            row(
                systemImage: "mappin.and.ellipse", label: String(localized: "Где ищем"),
                value: String(localized: "Сначала \(places.city(search.cityCode))"),
                note: String(localized: "Если рядом никого, через \(RussianPlural.seconds(roulette.cityWaitSeconds)) — весь \(places.country).")
            ) { EmptyView() }
            if let evening = roulette.status?.evening {
                divider
                row(
                    systemImage: "bell", label: String(localized: "Вечер рулетки"),
                    value: String(localized: "Напоминать в \(evening.startTime)"),
                    note: String(localized: "Больше всего людей с \(evening.startTime) до \(evening.endTime).")
                ) {
                    Toggle("Напоминать", isOn: Binding(
                        get: { roulette.status?.reminder ?? false },
                        set: { roulette.setReminder($0) }
                    ))
                    .labelsHidden()
                    .tint(Color.brand)
                    .padding(.top, 12)
                }
            }
            Spacer(minLength: 16)
            Button("Готово") {
                if ages != search.ageMin...search.ageMax {
                    Task { await roulette.setAges(min: ages.lowerBound, max: ages.upperBound) }
                }
                dismiss()
            }
            .buttonStyle(.appPrimary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        Divider().overlay(Color.appLine)
    }

    private func icon(_ systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 22)
            .padding(.top, 2)
    }

    private func row<Trailing: View>(systemImage: String, label: String, value: String, note: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(systemImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.app(.callout, weight: .semibold))
                Text(note)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 14)
    }
}

/// Двойной ползунок возраста: «от» не уходит правее «до». Каждый бегунок VoiceOver меняет жестом вверх-вниз.
private struct RouletteAgeRangeSlider: View {
    @Binding var range: ClosedRange<Int>
    let bounds: ClosedRange<Int>

    private enum End { case lower, upper }
    private let knob: CGFloat = 28
    /// Область касания бегунка больше его самого — 44 pt, как у любой кнопки.
    private let hitSize: CGFloat = 44

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.width - knob
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appElevated)
                    .frame(height: 4)
                    .padding(.horizontal, knob / 2)
                Capsule()
                    .fill(Color.brand)
                    .frame(width: position(range.upperBound, track) - position(range.lowerBound, track), height: 4)
                    .offset(x: position(range.lowerBound, track) + knob / 2)
                thumb(.lower, track: track)
                thumb(.upper, track: track)
            }
            .frame(height: hitSize)
            .coordinateSpace(name: Self.space)
        }
        .frame(height: hitSize)
    }

    private static let space = "rouletteAgeSlider"

    private func position(_ value: Int, _ track: CGFloat) -> CGFloat {
        CGFloat(value - bounds.lowerBound) / CGFloat(bounds.upperBound - bounds.lowerBound) * track
    }

    private func value(at x: CGFloat, _ track: CGFloat) -> Int {
        let fraction = min(max((x - knob / 2) / track, 0), 1)
        return bounds.lowerBound + Int((fraction * CGFloat(bounds.upperBound - bounds.lowerBound)).rounded())
    }

    private func set(_ end: End, to value: Int) {
        switch end {
        case .lower: range = min(max(value, bounds.lowerBound), range.upperBound)...range.upperBound
        case .upper: range = range.lowerBound...max(min(value, bounds.upperBound), range.lowerBound)
        }
    }

    private func thumb(_ end: End, track: CGFloat) -> some View {
        let current = end == .lower ? range.lowerBound : range.upperBound
        return Circle()
            .fill(.white)
            .frame(width: knob, height: knob)
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .frame(width: hitSize, height: hitSize)
            .contentShape(Rectangle())
            .offset(x: position(current, track) - (hitSize - knob) / 2)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.space))
                    .onChanged { set(end, to: value(at: $0.location.x, track)) }
            )
            .accessibilityElement()
            .accessibilityLabel(end == .lower ? String(localized: "Возраст от") : String(localized: "Возраст до"))
            .accessibilityValue("\(current)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(end, to: current + 1)
                case .decrement: set(end, to: current - 1)
                @unknown default: break
                }
            }
    }
}

// MARK: - Поиск

private struct RouletteSearchView: View {
    @ObservedObject var roulette: RouletteViewModel
    let mode: RouletteMode
    let places: RoulettePlaces

    var body: some View {
        VStack(spacing: 0) {
            modeChip
                .padding(.top, 22)

            Spacer(minLength: 12)
            RouletteStage(dots: roulette.status?.online?.count(of: mode) ?? 0, glow: 0.28, spinning: true) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    RouletteSearchTimer(mode: mode, elapsed: context.date.timeIntervalSince(roulette.searchStartedAt))
                }
            }
            Text(title)
                .font(.display(size: 21))
                .padding(.top, 4)
            if let whom {
                Text(String(localized: "\(whom) · по «Кого ищу»"))
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                details(now: context.date)
            }
            .padding(.top, 16)
            .padding(.horizontal, 16)

            if let notice = roulette.notice {
                Text(notice)
                    .font(.app(.footnote, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
                    .padding(.horizontal, 20)
            }
            Spacer(minLength: 24)

            Button("Отменить") { roulette.stop() }
                .buttonStyle(.appSecondary)
                .frame(width: 200)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity)
        .background(AppBackground())
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(RouletteViewModel.onlineRefreshInterval))
                await roulette.refreshOnline()
            }
        }
    }

    /// «Видео · 9 онлайн».
    private var modeChip: some View {
        let name = mode == .video ? String(localized: "Видео") : String(localized: "Переписка")
        let text = roulette.status?.online.map { String(localized: "\(name) · \($0.count(of: mode)) онлайн") } ?? name
        return Label {
            Text(text).monospacedDigit()
        } icon: {
            Image(systemName: mode == .video ? "video" : "bubble.left")
                .foregroundStyle(Color.brand)
        }
        .font(.app(.subheadline, weight: .semibold))
        .padding(.leading, 10)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(Color.appSurface, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
    }

    private var lookingForFemale: Bool { roulette.status?.search?.lookingFor == "FEMALE" }

    private var title: String {
        lookingForFemale ? String(localized: "Ищем собеседницу…") : String(localized: "Ищем собеседника…")
    }

    /// «Девушки 21–31 год» — по кому сервер ищет сейчас (после «Расширить» — шире).
    private var whom: String? {
        guard let ages = roulette.searchAges else { return nil }
        let who = lookingForFemale ? String(localized: "Девушки") : String(localized: "Парни")
        return "\(who) \(ages.lowerBound)–\(RussianPlural.years(ages.upperBound))"
    }

    /// Первые секунды — шаги «свой город → вся страна»; долго никого — предложение расширить; расширили — итог.
    @ViewBuilder
    private func details(now: Date) -> some View {
        let elapsed = now.timeIntervalSince(roulette.searchStartedAt)
        if roulette.searchExpanded {
            expandedNote
        } else if elapsed >= RouletteViewModel.expandOfferAfter, let ages = roulette.expandedAges {
            expandCard(ages: ages)
        } else {
            steps(now: now)
        }
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
                DatingProfileDetailView(profile: profile, catalog: dating.catalog, viewer: dating.profile?.shared)
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
private extension Color {
    /// Зелёный «в сети» из макета рулетки.
    static let rouletteOnline = Color(light: 0x2E9A5E, dark: 0x4CAF78)
    static let rouletteOnlineText = Color(light: 0x1F7A47, dark: 0x7FD8A4)
}
