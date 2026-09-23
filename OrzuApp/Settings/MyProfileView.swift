import SwiftUI

/// Вкладка «Мой профиль»: карточка с аватаром и именем, анкета знакомств и «Кого ищу».
/// Настройки аккаунта — шестерёнкой в верхней панели.
struct MyProfileView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject var dating: DatingViewModel
    @State private var displayName = ""
    @State private var showDatingEditor = false
    @State private var datingSettingsError: String?
    @State private var showPreview = false
    @State private var showSelfie = false
    @State private var showSafety = false

    init(dating: DatingViewModel, onProfileChanged: @escaping (User) -> Void) {
        self.dating = dating
        _viewModel = StateObject(wrappedValue: SettingsViewModel(onProfileChanged: onProfileChanged))
    }

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                profileSection(settings)
                if dating.stage == .ready {
                    quickActions
                }
                datingSection
            } else if viewModel.isBusy {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Мой профиль")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { SettingsView(viewModel: viewModel) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Настройки")
            }
        }
        .task { await viewModel.load() }
        // Вкладку знакомств могли ещё не открывать — анкета нужна и здесь.
        .task { if dating.stage == .loading { await dating.load() } }
        // «Кого ищу» появляется, когда анкета готова: сразу или после того, как её заполнили.
        .task(id: dating.stage) {
            guard dating.stage == .ready, dating.lookingFor == nil else { return }
            do {
                try await dating.loadLookingFor()
            } catch {
                datingSettingsError = error.localizedDescription
            }
        }
        .sheet(isPresented: $showDatingEditor) {
            NavigationStack { DatingProfileEditorView(dating: dating) }
        }
        .sheet(isPresented: $showPreview) {
            NavigationStack { DatingProfilePreviewView(catalog: dating.catalog) }
        }
        .sheet(isPresented: $showSelfie) {
            NavigationStack { SelfieVerificationView(dating: dating) }
        }
        .sheet(isPresented: $showSafety) {
            NavigationStack { SafetyView() }
        }
        .alert("Ошибка", isPresented: .constant(datingSettingsError != nil)) {
            Button("Ок") { datingSettingsError = nil }
        } message: {
            Text(datingSettingsError ?? "")
        }
        .onChange(of: viewModel.settings?.displayName) { _, name in displayName = name ?? "" }
    }

    /// Профиль — крупной карточкой по центру, как Apple ID в системных настройках.
    private func profileSection(_ settings: AccountSettings) -> some View {
        Section {
            VStack(spacing: 10) {
                // Аватар — главное одобренное фото анкеты, поэтому меняют его в анкете.
                Button { showDatingEditor = true } label: {
                    AvatarView(avatarUrl: settings.avatarUrl, name: settings.displayName, size: 108)
                        .padding(4)
                        .overlay(Circle().strokeBorder(.brandFill, lineWidth: 2.5))
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.brandFill, in: Circle())
                                .overlay(Circle().strokeBorder(Color.appBackground, lineWidth: 3))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Фото анкеты")
                Text("Аватар — главное фото анкеты, виден всем сразу. Значок «проверен» появится после проверки модератором.")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Имя", text: $displayName)
                    .font(.display(.title2))
                    .multilineTextAlignment(.center)
                    .onSubmit { Task { await viewModel.saveDisplayName(displayName) } }
                    .submitLabel(.done)
                Text("@\(settings.username)").font(.app(.subheadline)).foregroundStyle(.secondary)
                if dating.stage == .ready {
                    statusChips
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)

            if displayName.trimmingCharacters(in: .whitespaces) != settings.displayName && !displayName.isEmpty {
                Button("Сохранить имя") { Task { await viewModel.saveDisplayName(displayName) } }
            }
            NavigationLink { UsernameSettingsView(viewModel: viewModel, current: settings.username) } label: {
                LabeledContent("Имя пользователя", value: "@\(settings.username)")
            }
        }
    }

    /// Анкета знакомств — часть профиля: её и «Кого ищу» правят отсюда же. Фильтры — у сетки анкет, у ленты их нет.
    @ViewBuilder
    private var datingSection: some View {
        Section {
            switch dating.stage {
            case .loading:
                ProgressView().frame(maxWidth: .infinity)
            case .rules:
                Text("Чтобы заполнить анкету, примите правила сообщества во вкладке «Знакомства».")
                    .foregroundStyle(.secondary)
            case .noProfile:
                Button { showDatingEditor = true } label: {
                    SettingsLabel("Заполнить анкету", systemImage: "heart.text.square.fill", color: .brand)
                }
            case .ready:
                if let lookingFor = dating.lookingFor {
                    Picker(selection: Binding(get: { lookingFor }, set: saveLookingFor)) {
                        ForEach(dating.catalog?.genders ?? []) { gender in
                            Text(gender.name).tag(gender.code)
                        }
                    } label: {
                        SettingsLabel("Кого ищу", systemImage: "person.2.fill", color: .champagne)
                    }
                }
                Toggle(isOn: Binding(get: { dating.profile?.hasLocation ?? false }, set: saveShowsDistance)) {
                    SettingsLabel("Расстояние до анкет", systemImage: "location.fill", color: .brand)
                }
                .tint(DatingStyle.rose)
                Toggle(isOn: Binding(get: { dating.profile?.hidden ?? false }, set: saveHidden)) {
                    SettingsLabel("Скрыть анкету", systemImage: "eye.slash.fill", color: .champagne)
                }
                .tint(DatingStyle.rose)
            }
        } header: {
            Text("Знакомства")
        } footer: {
            if dating.stage == .ready {
                Text("Расстояние видно только тем, у кого оно тоже включено. Точное место не хранится — только район около километра. Скрытую анкету не видят в ленте, а чаты и пары остаются.")
            }
        }
        .tint(.primary)
    }

    /// Под именем: проверена ли анкета и видят ли её другие — два главных вопроса о своём профиле.
    private var statusChips: some View {
        HStack(spacing: 8) {
            if dating.needsSelfie {
                statusChip(dating.selfiePending ? "Селфи на проверке" : "Не проверена", systemImage: dating.selfiePending ? "clock.fill" : "seal", tint: .secondary)
            } else {
                statusChip("Проверена", systemImage: "checkmark.seal.fill", tint: .champagne)
            }
            if dating.profile?.visibleToOthers == true {
                statusChip("Видна в ленте", systemImage: "eye.fill", tint: .brand)
            } else {
                statusChip("Скрыта", systemImage: "eye.slash.fill", tint: .secondary)
            }
        }
    }

    private func statusChip(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }

    /// Частые действия с анкетой — плитками, чтобы не искать их в длинном редакторе.
    private var quickActions: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                actionTile("Анкета", subtitle: "Фото и о себе", systemImage: "heart.text.square.fill", tint: .brand) { showDatingEditor = true }
                actionTile("Как меня видят", subtitle: "Глазами других", systemImage: "eye.fill", tint: .brand) { showPreview = true }
                actionTile("Проверка", subtitle: dating.needsSelfie ? (dating.selfiePending ? "Ждёт модератора" : "Пройти по селфи") : "Пройдена", systemImage: "checkmark.seal.fill", tint: .champagne) { showSelfie = true }
                actionTile("Безопасность", subtitle: "Контакты и SOS", systemImage: "shield.lefthalf.filled", tint: .champagne) { showSafety = true }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    private func actionTile(_ title: String, subtitle: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 38, height: 38)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.app(.subheadline, weight: .semibold)).foregroundStyle(.primary)
                    Text(subtitle).font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .appCard(cornerRadius: 20, padding: 14)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func saveShowsDistance(_ enabled: Bool) {
        Task {
            do {
                try await dating.setShowsDistance(enabled)
            } catch {
                datingSettingsError = error.localizedDescription
            }
        }
    }

    private func saveHidden(_ hidden: Bool) {
        Task {
            do {
                try await dating.setHidden(hidden)
            } catch {
                datingSettingsError = error.localizedDescription
            }
        }
    }

    private func saveLookingFor(_ gender: String) {
        Task {
            do {
                try await dating.setLookingFor(gender)
            } catch {
                datingSettingsError = error.localizedDescription
            }
        }
    }
}
