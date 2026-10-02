import SwiftUI

/// Вкладка «Профиль»: кто я, видят ли мою анкету и что для этого осталось, анкета, «Кого ищу», справка и настройки.
/// Переключатели знакомств, имя и логин — в «Настройках»: здесь только главное.
struct MyProfileView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject var dating: DatingViewModel
    @State private var showDatingEditor = false
    @State private var datingSettingsError: String?
    @State private var showSelfie = false
    /// Экран запроса селфи открывается сам один раз: «Позже» — выбор человека, повторно не навязываем.
    @State private var selfieRequestShown = false
    @ObservedObject private var push = PushManager.shared

    init(dating: DatingViewModel, onProfileChanged: @escaping (User) -> Void) {
        self.dating = dating
        _viewModel = StateObject(wrappedValue: SettingsViewModel(onProfileChanged: onProfileChanged))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let settings = viewModel.settings {
                    identity(settings)
                } else if viewModel.isBusy {
                    ProgressView().frame(maxWidth: .infinity)
                }
                statusCard
                rows
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.app(.footnote))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .appScreenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { await viewModel.load() }
        // Вкладку знакомств могли ещё не открывать — анкета нужна и здесь.
        .task { if dating.stage == .loading { await dating.load() } }
        // «Кого ищу» появляется, когда анкета готова: сразу или после того, как её заполнили.
        .task(id: dating.stage) {
            guard dating.stage == .ready, dating.lookingFor == nil || dating.criteria == nil else { return }
            do {
                try await dating.loadLookingFor()
                try await dating.loadCriteria()
            } catch {
                datingSettingsError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showDatingEditor) {
            NavigationStack { DatingProfileEditorView(dating: dating) }
        }
        .sheet(isPresented: $showSelfie) {
            NavigationStack { SelfieVerificationView(dating: dating) }
        }
        // Модератор попросил новое селфи — показываем его экран, как только человек в профиле.
        .task(id: dating.selfieRequested) {
            guard dating.selfieRequested, !selfieRequestShown else { return }
            selfieRequestShown = true
            showSelfie = true
        }
        // Нажали на push с просьбой модератора — экран открываем, даже если уже откладывали.
        .onChange(of: push.pendingSelfieRequest) { _, pending in
            guard pending else { return }
            push.pendingSelfieRequest = false
            Task { await dating.refreshVerification() }
            selfieRequestShown = true
            showSelfie = true
        }
        .alert("Ошибка", isPresented: .constant(datingSettingsError != nil)) {
            Button("Ок") { datingSettingsError = nil }
        } message: {
            Text(datingSettingsError ?? "")
        }
    }

    /// Заголовок и заметная кнопка «Настройки» — шестерёнку без подписи люди не находили.
    private var header: some View {
        HStack(spacing: 12) {
            Text("Мой профиль")
                .font(.display(size: 30, weight: .bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            NavigationLink { SettingsView(viewModel: viewModel, dating: dating) } label: {
                Label("Настройки", systemImage: "gearshape")
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 42)
                    .background(Color.appSurface, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 4)
        .padding(.top, 6)
    }

    /// Аватар — главное одобренное фото анкеты, поэтому нажатие открывает анкету.
    private func identity(_ settings: AccountSettings) -> some View {
        HStack(spacing: 16) {
            Button { showDatingEditor = true } label: {
                AvatarView(avatarUrl: settings.avatarUrl, name: settings.displayName, size: 72)
                    .padding(4)
                    .overlay(Circle().strokeBorder(.brandFill, lineWidth: 2.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Моя анкета")
            VStack(alignment: .leading, spacing: 4) {
                Text(settings.displayName)
                    .font(.display(size: 22, weight: .bold))
                    .lineLimit(1)
                Text("@\(settings.username)")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                if dating.stage == .ready {
                    verificationChip
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var verificationChip: some View {
        if !dating.needsSelfie {
            chip(String(localized: "Проверена"), systemImage: "checkmark.seal.fill")
        } else if dating.selfiePending {
            chip(String(localized: "На проверке"), systemImage: "hourglass")
        } else if dating.selfieRequested {
            chip(String(localized: "Нужно новое селфи"), systemImage: "camera.fill")
        } else {
            chip(String(localized: "Не проверена"), systemImage: "seal")
        }
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.app(.footnote, weight: .semibold))
            .foregroundStyle(Color.champagne)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.champagneSoft, in: Capsule())
    }

    /// Главный вопрос о своём профиле — видят ли меня в ленте, а если нет, то что осталось сделать.
    @ViewBuilder
    private var statusCard: some View {
        switch dating.stage {
        case .loading:
            EmptyView()
        case .rules:
            infoCard(
                systemImage: "list.bullet.clipboard", title: String(localized: "Анкеты пока нет"),
                text: String(localized: "Примите правила сообщества во вкладке «Знакомства» — и заполните анкету.")
            )
        case .noProfile:
            Button { showDatingEditor = true } label: {
                infoCard(
                    systemImage: "heart.text.square", title: String(localized: "Заполните анкету"),
                    text: String(localized: "Без анкеты вас не видят в ленте и «Поиске».")
                )
            }
            .buttonStyle(.plain)
        case .ready:
            if let profile = dating.profile {
                if profile.visibleToOthers {
                    infoCard(
                        systemImage: "eye", title: String(localized: "Вашу анкету видят"),
                        text: String(localized: "Её показывают тем, кому вы подходите.")
                    )
                } else {
                    hiddenCard(profile)
                }
            }
        }
    }

    private func infoCard(systemImage: String, title: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Color.champagne)
                .frame(width: 48, height: 48)
                .background(Color.champagneSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.body, weight: .bold))
                Text(text)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }

    /// «Пока вас не видят в ленте» — чек-лист: что готово, что на проверке и что сделать самому.
    private func hiddenCard(_ profile: DatingProfileMine) -> some View {
        let issues = Set(profile.visibilityIssues)
        let photosPending = profile.photos.contains { $0.status == .pending }
        let onlyWaiting = issues.isSubset(of: [.notVerified, .noApprovedPhotos])
            && (!issues.contains(.notVerified) || dating.selfiePending)
            && (!issues.contains(.noApprovedPhotos) || photosPending)
        return VStack(alignment: .leading, spacing: 12) {
            Label("Пока вас не видят в ленте", systemImage: "eye.slash")
                .font(.app(.body, weight: .bold))
                .labelStyle(StatusTitleLabelStyle())
            VStack(alignment: .leading, spacing: 10) {
                checkLine(.done, String(localized: "Анкета заполнена"))
                if !issues.contains(.noApprovedPhotos) {
                    checkLine(.done, String(localized: "Фото добавлено"))
                } else if photosPending {
                    checkLine(.waiting, String(localized: "Фото на проверке"))
                } else {
                    Button { showDatingEditor = true } label: {
                        checkLine(.todo, String(localized: "Добавьте фото — прежние не прошли проверку"), tappable: true)
                    }
                    .buttonStyle(.plain)
                }
                if !issues.contains(.notVerified) {
                    checkLine(.done, String(localized: "Селфи проверено"))
                } else if dating.selfiePending {
                    checkLine(.waiting, Text("Селфи на проверке — ") + Text("до 24 часов").bold())
                } else {
                    Button { showSelfie = true } label: {
                        checkLine(.todo, String(localized: "Пройдите проверку по селфи"), tappable: true)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(profile.visibilityIssues.filter { ![.notVerified, .noApprovedPhotos].contains($0) }, id: \.self) { issue in
                    checkLine(.todo, issue.explanation)
                }
            }
            Group {
                if onlyWaiting {
                    Text("Как только модератор всё проверит, анкета появится в ленте со значком «проверен». Переписка и «Поиск» работают уже сейчас.")
                } else {
                    Text("Переписка и «Поиск» работают уже сейчас.")
                }
            }
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.champagneSoft, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.champagne.opacity(0.45), lineWidth: 1))
    }

    private enum CheckState {
        case done, waiting, todo

        var systemImage: String {
            switch self {
            case .done: "checkmark"
            case .waiting: "hourglass"
            case .todo: "exclamationmark.circle"
            }
        }
    }

    private func checkLine(_ state: CheckState, _ title: String, tappable: Bool = false) -> some View {
        checkLine(state, Text(title), tappable: tappable)
    }

    private func checkLine(_ state: CheckState, _ title: Text, tappable: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: state.systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(state == .todo ? Color.brand : Color.champagne)
                .frame(width: 20)
            title
                .font(.app(.subheadline))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if tappable {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var rows: some View {
        VStack(spacing: 0) {
            if dating.stage == .ready {
                Button { showDatingEditor = true } label: {
                    ProfileRow(
                        systemImage: "heart.text.square", tint: .brand,
                        title: String(localized: "Моя анкета"), subtitle: String(localized: "Фото, о себе, интересы"),
                        value: dating.completeness.map { "\($0.percent)%" }
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(Color.appLine)
                NavigationLink { SearchCriteriaView(dating: dating) {} } label: {
                    ProfileRow(
                        systemImage: "person.2", tint: .champagne,
                        title: String(localized: "Кого ищу"), subtitle: String(localized: "Влияет на ленту «Знакомства»"),
                        value: dating.criteriaSummary
                    )
                }
                .buttonStyle(.plain)
                Divider().overlay(Color.appLine)
            }
            NavigationLink { HowItWorksView() } label: {
                ProfileRow(
                    systemImage: "info.circle", tint: .brand,
                    title: String(localized: "Как это работает"), subtitle: String(localized: "Лайки, пары, проверка, «Путь к браку»")
                )
            }
            .buttonStyle(.plain)
            Divider().overlay(Color.appLine)
            NavigationLink { SettingsView(viewModel: viewModel, dating: dating) } label: {
                ProfileRow(
                    systemImage: "gearshape", tint: .champagne,
                    title: String(localized: "Настройки"), subtitle: String(localized: "Приватность, уведомления, почта, пароль, выход")
                )
            }
            .buttonStyle(.plain)
        }
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
    }
}

/// Заголовок карточки статуса: значок того же размера, что строки чек-листа под ним.
private struct StatusTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(Color.champagne)
            configuration.title
        }
    }
}

/// Строка профиля: значок на подложке, название с пояснением, справа — значение и стрелка.
struct ProfileRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let subtitle: String
    var value: String?

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.body, weight: .medium))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let value {
                Text(value)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
