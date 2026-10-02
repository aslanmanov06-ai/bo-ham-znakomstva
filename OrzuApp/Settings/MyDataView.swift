import SwiftUI

/// «Мои данные» (макет «Настройки — „Мои данные“»): имя, username, дата рождения, пол, телефон и почта.
/// Дату рождения меняют раз в 90 дней, пол — только через поддержку.
struct MyDataView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject var dating: DatingViewModel

    var body: some View {
        Form {
            if let settings = viewModel.settings {
                Section {
                    NavigationLink { DisplayNameEditView(viewModel: viewModel, current: settings.displayName) } label: {
                        DataRow(String(localized: "Имя"), value: settings.displayName, systemImage: "person.fill", color: .brand)
                    }
                    NavigationLink { UsernameSettingsView(viewModel: viewModel, current: settings.username) } label: {
                        DataRow(String(localized: "Логин"), value: "@\(settings.username)", systemImage: "at", color: .brand)
                    }
                    if let profile = dating.profile {
                        NavigationLink { BirthDateEditView(dating: dating) } label: {
                            DataRow(
                                String(localized: "Дата рождения"),
                                value: CalendarDate.date(from: profile.birthDate)?.formatted(date: .long, time: .omitted) ?? profile.birthDate,
                                hint: String(localized: "Менять можно раз в 90 дней"),
                                systemImage: "birthday.cake.fill",
                                color: .brand
                            )
                        }
                        HStack {
                            DataRow(
                                String(localized: "Пол"),
                                value: dating.catalog?.genders.name(of: profile.shared.gender) ?? profile.shared.gender,
                                hint: String(localized: "Изменить — через поддержку"),
                                systemImage: "person.2.fill",
                                color: .brand
                            )
                            Spacer()
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.tertiary)
                                .accessibilityLabel("Не меняется")
                        }
                    }
                }
                Section {
                    NavigationLink { PhoneEditView(viewModel: viewModel, current: settings.phone) } label: {
                        DataRow(
                            String(localized: "Телефон"),
                            value: settings.phone ?? String(localized: "Не указан"),
                            hint: String(localized: "Никому не показывается"),
                            systemImage: "phone.fill",
                            color: .champagne
                        )
                    }
                    NavigationLink { EmailSettingsView(viewModel: viewModel) } label: {
                        DataRow(
                            String(localized: "Почта"),
                            value: settings.email ?? String(localized: "Не указана"),
                            hint: String(localized: "Для входа и восстановления пароля"),
                            systemImage: "envelope.fill",
                            color: .champagne
                        )
                    }
                } footer: {
                    Text("Город, рост и остальное — в «Профиль → Моя анкета». Кого вы ищете — в «Профиль → Кого ищу».")
                }
            }
        }
        .appScreenBackground()
        .navigationTitle("Мои данные")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Строка данных: подпись сверху, значение крупнее, пояснение мелко снизу.
private struct DataRow: View {
    let title: String
    let value: String
    var hint: String?
    let systemImage: String
    let color: Color

    init(_ title: String, value: String, hint: String? = nil, systemImage: String, color: Color) {
        self.title = title
        self.value = value
        self.hint = hint
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.app(.body, weight: .semibold))
                if let hint {
                    Text(hint)
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

private struct DisplayNameEditView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let current: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        Form {
            Section {
                TextField("Имя", text: $name)
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                Text("Имя видно в анкете и в чатах.")
            }
            Button("Сохранить", action: save)
                .disabled(!canSave)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Имя")
        .onAppear { name = current }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        !trimmed.isEmpty && trimmed.count <= 64 && trimmed != current && !viewModel.isBusy
    }

    private func save() {
        guard canSave else { return }
        Task {
            await viewModel.saveDisplayName(trimmed)
            if viewModel.errorMessage == nil { dismiss() }
        }
    }
}

/// Дата рождения: раз в 90 дней и только 18+. Пока смена недоступна — показываем, с какого дня можно.
private struct BirthDateEditView: View {
    @ObservedObject var dating: DatingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()
    @State private var confirm = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                DatePicker("Дата рождения", selection: $date, in: range, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .disabled(lockedUntil != nil)
            } footer: {
                if let lockedUntil {
                    Text("Дату уже меняли. Следующий раз — с \(lockedUntil.formatted(date: .long, time: .omitted)).")
                } else {
                    Text("Менять дату рождения можно раз в 90 дней. Знакомства — с \(DatingLimits.minAge) лет.")
                }
            }
            Button("Сохранить") { confirm = true }
                .disabled(!canSave)
        }
        .appScreenBackground()
        .navigationTitle("Дата рождения")
        .onAppear {
            if let profile = dating.profile, let saved = CalendarDate.date(from: profile.birthDate) { date = saved }
        }
        .confirmationDialog("Сохранить новую дату рождения?", isPresented: $confirm, titleVisibility: .visible) {
            Button("Сохранить") { save() }
        } message: {
            Text("Следующий раз изменить её можно будет через 90 дней.")
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// nil — менять уже можно.
    private var lockedUntil: Date? {
        guard let from = dating.profile?.birthDateEditableFrom, from > .now else { return nil }
        return from
    }

    private var range: ClosedRange<Date> {
        let calendar = Calendar.current
        let latest = calendar.date(byAdding: .year, value: -DatingLimits.minAge, to: .now) ?? .now
        let earliest = calendar.date(byAdding: .year, value: -DatingLimits.maxAge, to: .now) ?? .distantPast
        return earliest...latest
    }

    private var canSave: Bool {
        guard lockedUntil == nil, !isSaving, let profile = dating.profile else { return false }
        return CalendarDate.string(from: date) != profile.birthDate
    }

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await dating.setBirthDate(date)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Телефон в международном формате, без подтверждения по SMS — как при регистрации.
private struct PhoneEditView: View {
    @ObservedObject var viewModel: SettingsViewModel
    let current: String?
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""

    var body: some View {
        Form {
            Section {
                TextField("+992901234567", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .submitLabel(.done)
                    .onSubmit(save)
            } footer: {
                if !phone.isEmpty && !isValid {
                    Text("Номер — в международном формате, например +992901234567.").foregroundStyle(.red)
                } else {
                    Text("Номер никому не показывается.")
                }
            }
            Button("Сохранить", action: save)
                .disabled(!canSave)
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Телефон")
        .onAppear { phone = current ?? "" }
    }

    /// Пробелы, скобки и дефисы — для удобства ввода; на сервер уходят только «+» и цифры.
    private var normalized: String {
        phone.filter { $0 == "+" || $0.isNumber }
    }

    private var isValid: Bool {
        normalized.range(of: #"^\+[1-9]\d{7,14}$"#, options: .regularExpression) != nil
    }

    private var canSave: Bool {
        isValid && normalized != current && !viewModel.isBusy
    }

    private func save() {
        guard canSave else { return }
        Task {
            if await viewModel.savePhone(normalized) { dismiss() }
        }
    }
}
