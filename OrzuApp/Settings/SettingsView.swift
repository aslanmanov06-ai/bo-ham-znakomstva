import SwiftUI

/// Аккаунт и приложение: открываются шестерёнкой из «Моего профиля», модель у них общая.
struct SettingsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var confirmLogout = false

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                Section("Аккаунт") {
                    NavigationLink { PrivacySettingsView(viewModel: viewModel) } label: {
                        SettingsLabel("Приватность", systemImage: "hand.raised.fill", color: .brand)
                    }
                    NavigationLink { EmailSettingsView(viewModel: viewModel) } label: {
                        LabeledContent {
                            Text(settings.email ?? "не указана")
                        } label: {
                            SettingsLabel("Резервная почта", systemImage: "envelope.fill", color: .champagne)
                        }
                    }
                    NavigationLink { ChangePasswordView(viewModel: viewModel, hasPassword: settings.hasPassword) } label: {
                        LabeledContent {
                            Text(settings.hasPassword ? "" : "не задан")
                        } label: {
                            SettingsLabel("Пароль", systemImage: "key.fill", color: .champagne)
                        }
                    }
                    if settings.googleLinked {
                        LabeledContent {
                            Text("привязан")
                        } label: {
                            SettingsLabel("Google", systemImage: "g.circle.fill", color: .brand)
                        }
                    }
                    NavigationLink { SessionsView() } label: {
                        SettingsLabel("Активные сеансы", systemImage: "iphone", color: .brand)
                    }
                }
                Section("Приложение") {
                    NavigationLink { NotificationSettingsView(viewModel: viewModel) } label: {
                        SettingsLabel("Уведомления", systemImage: "bell.fill", color: .champagne)
                    }
                    NavigationLink { AppearanceView() } label: {
                        SettingsLabel("Оформление", systemImage: "paintpalette.fill", color: .brand)
                    }
                }
                Section("Помощь") {
                    NavigationLink { SupportView() } label: {
                        SettingsLabel("Поддержка", systemImage: "questionmark.circle.fill", color: .brand)
                    }
                    ForEach([LegalDocumentKind.rules, .privacy, .terms]) { kind in
                        NavigationLink { LegalDocumentView(kind: kind) } label: {
                            SettingsLabel(kind.title, systemImage: kind.systemImage, color: .champagne)
                        }
                    }
                }
            } else if viewModel.isBusy {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Section {
                Button(role: .destructive) { confirmLogout = true } label: {
                    SettingsLabel("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right", color: .red)
                }
                if viewModel.settings != nil {
                    NavigationLink { AccountRemovalView(viewModel: viewModel) } label: {
                        LabeledContent {
                            Text(viewModel.settings?.deactivated == true ? "отключён" : "")
                        } label: {
                            SettingsLabel("Отключить или удалить аккаунт", systemImage: "trash.fill", color: .red)
                                .foregroundStyle(.red)
                        }
                    }
                }
            } footer: {
                Text("Бо Хам · версия \(Self.appVersion)")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
        }
        .appScreenBackground()
        .navigationTitle("Настройки")
        .confirmationDialog("Выйти из аккаунта?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) { Task { await authViewModel.logout() } }
        }
    }

    private static let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
}

/// Строка настроек: значок фирменного цвета на лёгкой подложке того же цвета. Общая для «Моего профиля» и настроек.
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

struct PrivacySettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                Section {
                    Picker("Кто может мне писать", selection: binding(settings.messagePrivacy) { PrivacyUpdate(messagePrivacy: $0) }) {
                        // «Никто» для сообщений то же, что «Знакомые»: уже открытые чаты работают, новые начать нельзя.
                        ForEach([PrivacyLevel.everyone, .contacts]) { Text($0.title).tag($0) }
                    }
                    Picker("Кто может добавлять в группы", selection: binding(settings.groupInvitePrivacy) { PrivacyUpdate(groupInvitePrivacy: $0) }) {
                        ForEach(PrivacyLevel.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    Text("Сообщения")
                } footer: {
                    Text("«Знакомые» — те, с кем у вас уже есть личный чат.")
                }

                Section {
                    Toggle("В мессенджере", isOn: toggle(settings.messengerSearchByUsername) { PrivacyUpdate(messengerSearchByUsername: $0) })
                    Toggle("В знакомствах", isOn: toggle(settings.datingSearchByUsername) { PrivacyUpdate(datingSearchByUsername: $0) })
                } header: {
                    Text("Находить меня по @username")
                } footer: {
                    Text("В мессенджере — без этого вам не напишут первыми те, у кого с вами ещё нет чата. В знакомствах — анкету не найдут по username, но в ленте она останется.")
                }

                Section {
                    NavigationLink { BlockedUsersView(viewModel: viewModel) } label: {
                        SettingsLabel("Чёрный список", systemImage: "hand.raised.fill", color: .brand)
                    }
                    DataExportButton()
                } footer: {
                    Text("Все данные аккаунта одним файлом JSON: анкета, пары, сообщения, настройки.")
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Приватность")
    }

    private func binding(_ current: PrivacyLevel, update: @escaping (PrivacyLevel) -> PrivacyUpdate) -> Binding<PrivacyLevel> {
        Binding(get: { current }, set: { value in Task { await viewModel.updatePrivacy(update(value)) } })
    }

    private func toggle(_ current: Bool, update: @escaping (Bool) -> PrivacyUpdate) -> Binding<Bool> {
        Binding(get: { current }, set: { value in Task { await viewModel.updatePrivacy(update(value)) } })
    }
}

struct UsernameSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let current: String
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 4) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        // Сервер хранит username строчными — показываем сразу так, как он сохранится.
                        .onChange(of: username) { username = username.lowercased() }
                        .submitLabel(.done)
                        .onSubmit(save)
                }
            } footer: {
                if !username.isEmpty && !UsernameRules.isValid(username) {
                    Text("3–32 символа: латинские буквы, цифры и «_».").foregroundStyle(.red)
                } else {
                    Text("По username вас находят в мессенджере и знакомствах, им же входят в приложение. Старый username освободится, и его сможет занять другой человек.")
                }
            }
            Button("Сохранить", action: save)
                .disabled(!canSave)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Имя пользователя")
        .onAppear { username = current }
    }

    private var canSave: Bool {
        UsernameRules.isValid(username) && username != current && !viewModel.isBusy
    }

    private func save() {
        guard canSave else { return }
        Task {
            if await viewModel.saveUsername(username) {
                dismiss()
            }
        }
    }
}

struct BlockedUsersView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            ForEach(viewModel.blockedUsers) { user in
                HStack {
                    AvatarView(avatarUrl: user.avatarUrl, name: user.displayName, size: 36)
                    VStack(alignment: .leading) {
                        Text(user.displayName)
                        Text("@\(user.username)").font(.app(.footnote)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Разблокировать") { Task { await viewModel.unblock(user) } }
                        .buttonStyle(.borderless)
                }
            }
        }
        .appScreenBackground()
        .overlay {
            if viewModel.blockedUsers.isEmpty && !viewModel.isBusy {
                ContentUnavailableView("Никто не заблокирован", systemImage: "hand.raised", description: Text("Заблокировать можно в личном чате: ⋯ → Заблокировать"))
            }
        }
        .navigationTitle("Чёрный список")
        .task { await viewModel.loadBlocked() }
    }
}

struct EmailSettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                if !settings.mailEnabled {
                    Text("На сервере пока не настроена отправка писем — привязать почту нельзя.")
                        .foregroundStyle(.secondary)
                }
                if let current = settings.email {
                    Section("Текущая почта") {
                        Text(current)
                        Button("Отвязать почту", role: .destructive) { Task { await viewModel.removeEmail() } }
                    }
                }
                Section {
                    TextField("name@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button(codeSent ? "Отправить код ещё раз" : "Отправить код") {
                        Task { codeSent = await viewModel.requestEmailCode(email) || codeSent }
                    }
                    .disabled(!settings.mailEnabled || !email.contains("@") || viewModel.isBusy)

                    if codeSent {
                        TextField("Код из письма", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                        Button("Подтвердить") {
                            Task {
                                if await viewModel.verifyEmail(code: code) {
                                    codeSent = false
                                    code = ""
                                    email = ""
                                }
                            }
                        }
                        .disabled(code.count != 6 || viewModel.isBusy)
                    }
                } header: {
                    Text(settings.email == nil ? "Привязать почту" : "Сменить почту")
                } footer: {
                    Text("По подтверждённой почте можно войти вместо username и восстановить забытый пароль.")
                }
            }
            if let infoMessage = viewModel.infoMessage {
                Text(infoMessage).foregroundStyle(.secondary)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Резервная почта")
    }
}

struct ChangePasswordView: View {
    @ObservedObject var viewModel: SettingsViewModel
    /// false — аккаунт из Google без пароля: текущий не спрашиваем, пароль задаётся впервые.
    let hasPassword: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var repeated = ""

    var body: some View {
        Form {
            Section {
                if hasPassword {
                    SecureField("Текущий пароль", text: $current)
                }
                SecureField("Новый пароль (мин. 8 символов)", text: $new)
                SecureField("Повторите новый пароль", text: $repeated)
            } footer: {
                if !repeated.isEmpty && new != repeated {
                    Text("Пароли не совпадают").foregroundStyle(.red)
                }
            }
            Button(hasPassword ? "Сменить пароль" : "Задать пароль") {
                Task {
                    if await viewModel.changePassword(current: hasPassword ? current : nil, new: new) {
                        dismiss()
                    }
                }
            }
            .disabled((hasPassword && current.isEmpty) || new.count < 8 || new != repeated || viewModel.isBusy)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle(hasPassword ? "Пароль" : "Задать пароль")
    }
}
