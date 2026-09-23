import SwiftUI

/// Своя анкета: создание пошаговым мастером и правка карточками.
/// Пол и дату рождения задают один раз — потом сервер их менять не даёт.
struct DatingProfileEditorView: View {
    @ObservedObject var dating: DatingViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var form = ProfileForm()
    /// Последняя сохранённая версия: кнопка «Сохранить» появляется, только когда форма от неё отличается.
    @State private var savedForm: ProfileForm?
    @State private var isSaving = false
    @State private var justCreated = false
    @State private var savedTicks = 0
    @State private var errorMessage: String?
    @State private var showPreview = false
    @State private var showSelfie = false
    @State private var showSafety = false
    @State private var confirmLeaveCouple = false

    private var isCreating: Bool { dating.profile == nil }

    var body: some View {
        Group {
            if isCreating {
                ProfileCreationFlow(form: $form, catalog: dating.catalog, isSaving: isSaving, onCreate: save)
            } else {
                editor
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isCreating)
        .navigationTitle(isCreating ? "Новая анкета" : "Моя анкета")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task {
            if let profile = dating.profile {
                form = ProfileForm(profile: profile)
                savedForm = form
            } else {
                form.countryCode = dating.catalog?.countries.first?.code ?? form.countryCode
            }
        }
        .sensoryFeedback(.success, trigger: savedTicks)
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                DatingProfilePreviewView(catalog: dating.catalog)
            }
        }
        .sheet(isPresented: $showSelfie) {
            NavigationStack {
                SelfieVerificationView(dating: dating)
            }
        }
        .sheet(isPresented: $showSafety) {
            NavigationStack {
                SafetyView()
            }
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Вернуться к поиску?", isPresented: $confirmLeaveCouple, titleVisibility: .visible) {
            Button("Вернуться к поиску", role: .destructive) { leaveCouple() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("«Мы нашли друг друга» снимется с вас обоих, а «Путь к браку» завершится.")
        }
    }

    // MARK: - Правка

    private var editor: some View {
        ScrollView {
            VStack(spacing: 14) {
                if justCreated {
                    createdBanner
                }
                if let completeness = dating.completeness {
                    CompletenessCard(completeness: completeness)
                }
                DatingPhotosSection(dating: dating)
                verificationCard
                shortcuts
                DatingSectionCard(title: "О себе", systemImage: "quote.opening") {
                    AboutFields(form: $form)
                }
                DatingSectionCard(title: "Семья и цели", systemImage: "heart.circle") {
                    GoalsFields(form: $form, catalog: dating.catalog)
                }
                DatingSectionCard(title: "Образ жизни", systemImage: "leaf") {
                    LifestyleFields(form: $form, catalog: dating.catalog)
                }
                DatingSectionCard(
                    title: "Интересы и вкусы",
                    systemImage: "star",
                    subtitle: "По ним считается совместимость — чем больше отметите, тем точнее подбор."
                ) {
                    TastesFields(form: $form, catalog: dating.catalog)
                }
                DatingSectionCard(title: "Где вы", systemImage: "mappin.and.ellipse") {
                    LocationFields(form: $form, catalog: dating.catalog)
                    Divider()
                    Toggle("Показывать расстояние до анкет", isOn: locationBinding)
                        .tint(DatingStyle.rose)
                }
                visibilityCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DatingBackdrop())
        .safeAreaInset(edge: .bottom) { saveBar }
        .animation(DatingStyle.spring, value: isDirty)
    }

    /// Сразу после создания: дальше нужны фото и селфи, иначе анкету не увидят.
    private var createdBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "party.popper.fill")
                .font(.app(.title))
                .symbolEffect(.bounce, value: justCreated)
            VStack(alignment: .leading, spacing: 3) {
                Text("Анкета создана!")
                    .font(.app(.headline))
                Text("Осталось добавить фото и подтвердить их селфи — после этого вас увидят в ленте.")
                    .font(.app(.footnote))
                    .opacity(0.9)
            }
        }
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DatingStyle.brandGradient, in: RoundedRectangle(cornerRadius: DatingStyle.tileCornerRadius, style: .continuous))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var verificationCard: some View {
        Button {
            showSelfie = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: verificationIcon)
                    .font(.app(.title2))
                    .foregroundStyle(verificationColor)
                    .frame(width: 44, height: 44)
                    .background(verificationColor.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verificationTitle)
                        .font(.app(.headline))
                        .foregroundStyle(.primary)
                    Text(verificationSubtitle)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                if dating.needsSelfie && !dating.selfiePending {
                    Image(systemName: "chevron.right")
                        .font(.app(.footnote, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!dating.needsSelfie)
    }

    private var verificationIcon: String {
        if !dating.needsSelfie { return "checkmark.seal.fill" }
        return dating.selfiePending ? "clock.fill" : "person.crop.square.badge.camera"
    }

    private var verificationColor: Color {
        if !dating.needsSelfie { return .champagne }
        return dating.selfiePending ? .champagne : DatingStyle.rose
    }

    private var verificationTitle: String {
        if !dating.needsSelfie { return "Анкета подтверждена" }
        return dating.selfiePending ? "Селфи на проверке" : "Подтвердите анкету селфи"
    }

    private var verificationSubtitle: String {
        if !dating.needsSelfie { return "Рядом с именем виден значок «проверен»." }
        return dating.selfiePending
            ? "Модератор сравнит селфи с фото анкеты — обычно это занимает несколько часов."
            : "Модератор сверит селфи с фото — так другие поймут, что вы настоящий."
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            shortcut("Как меня видят", systemImage: "eye") { showPreview = true }
            shortcut("Безопасность", systemImage: "shield.lefthalf.filled") { showSafety = true }
        }
    }

    private func shortcut(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.app(.title3))
                    .foregroundStyle(DatingStyle.rose)
                Text(title)
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private var visibilityCard: some View {
        DatingSectionCard(title: "Видимость", systemImage: "eye.circle", subtitle: visibilityNote) {
            Toggle("Скрыть анкету из ленты", isOn: $form.hidden)
                .tint(DatingStyle.rose)
            if dating.profile?.inCouple == true {
                Button("Вернуться к поиску", role: .destructive) { confirmLeaveCouple = true }
            }
        }
    }

    private var visibilityNote: String {
        if let profile = dating.profile, !profile.visibleToOthers {
            return profile.visibilityIssues.map(\.explanation).joined(separator: "\n")
        }
        return "Анкету видят те, кто подходит вашим фильтрам и чьим фильтрам подходите вы."
    }

    @ViewBuilder
    private var saveBar: some View {
        if isDirty {
            Button(action: save) {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text("Сохранить изменения")
                }
                .font(.app(.headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(DatingStyle.brandGradient, in: Capsule())
                .shadow(color: DatingStyle.rose.opacity(0.35), radius: 12, y: 6)
                .opacity(isValid ? 1 : 0.5)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(isSaving || !isValid)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    /// Расстояние до анкет считается по геопозиции; выключили — остаётся только город.
    private var locationBinding: Binding<Bool> {
        Binding(
            get: { dating.profile?.hasLocation ?? false },
            set: { setLocationEnabled($0) }
        )
    }

    // MARK: - Действия

    private var isDirty: Bool {
        savedForm != nil && form != savedForm
    }

    private var isValid: Bool {
        !form.cityCode.isEmpty && form.bio.count <= DatingLimits.maxBioLength
    }

    private func save() {
        isSaving = true
        let creating = isCreating
        Task {
            defer { isSaving = false }
            do {
                dating.apply(try await APIClient.shared.updateMyDatingProfile(form.update(isCreating: creating)))
                savedForm = form
                savedTicks += 1
                if creating {
                    // Новая анкета: дальше нужны фото и селфи — экран остаётся открытым уже в режиме правки.
                    justCreated = true
                    await dating.refreshVerification()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setLocationEnabled(_ enabled: Bool) {
        Task {
            do {
                try await dating.setShowsDistance(enabled)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func leaveCouple() {
        Task {
            do {
                try await APIClient.shared.leaveCouple()
                await dating.load()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Мастер создания

/// Новая анкета по шагам: на каждом экране — одна тема, поэтому заполнить её не страшно.
private struct ProfileCreationFlow: View {
    @Binding var form: ProfileForm
    let catalog: DatingCatalog?
    let isSaving: Bool
    let onCreate: () -> Void

    @State private var step = Step.basics
    @State private var movingForward = true
    /// Пол и дату рождения потом не изменить — поэтому их нужно выбрать явно, а не оставить значение по умолчанию.
    @State private var genderChosen = false
    @State private var birthDateChosen = false

    enum Step: Int, CaseIterable {
        case basics, goals, about, lifestyle, tastes

        var title: String {
            switch self {
            case .basics: "Давайте познакомимся"
            case .goals: "Что вы ищете"
            case .about: "Расскажите о себе"
            case .lifestyle: "Ваш образ жизни"
            case .tastes: "Что вам нравится"
            }
        }

        var subtitle: String {
            switch self {
            case .basics: "Пол и дату рождения потом изменить нельзя — проверьте их внимательно."
            case .goals: "Так мы покажем вас тем, кто ищет того же."
            case .about: "Пара искренних фраз о себе работает лучше любого фото."
            case .lifestyle: "Привычки — частая причина несовместимости, лучше знать заранее."
            case .tastes: "По интересам считается совместимость — отметьте всё, что откликается."
            }
        }

        var systemImage: String {
            switch self {
            case .basics: "person.fill"
            case .goals: "heart.fill"
            case .about: "text.quote"
            case .lifestyle: "leaf.fill"
            case .tastes: "star.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            progressHeader
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        stepHeader
                        stepContent
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .id(step)
                .transition(stepTransition)
            }
            .frame(maxHeight: .infinity)
            .clipped()
            bottomBar
        }
        .background(DatingBackdrop())
        .sensoryFeedback(.impact(weight: .light), trigger: step)
    }

    private var progressHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule()
                        .fill(item.rawValue <= step.rawValue ? AnyShapeStyle(DatingStyle.brandGradient) : AnyShapeStyle(Color.appElevated))
                        .frame(height: 5)
                }
            }
            Text("Шаг \(step.rawValue + 1) из \(Step.allCases.count)")
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .animation(DatingStyle.spring, value: step)
    }

    private var stepHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: step.systemImage)
                .font(.app(.title2, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(DatingStyle.brandGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: DatingStyle.rose.opacity(0.35), radius: 10, y: 5)
            Text(step.title)
                .font(.display(.title))
            Text(step.subtitle)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .basics:
            basics
        case .goals:
            DatingSectionCard(title: "Семья и цели", systemImage: "heart.circle") {
                GoalsFields(form: $form, catalog: catalog)
            }
        case .about:
            DatingSectionCard(title: "О себе", systemImage: "quote.opening") {
                AboutFields(form: $form)
            }
        case .lifestyle:
            DatingSectionCard(title: "Привычки и образование", systemImage: "leaf") {
                LifestyleFields(form: $form, catalog: catalog)
            }
        case .tastes:
            DatingSectionCard(title: "Интересы и вкусы", systemImage: "star") {
                TastesFields(form: $form, catalog: catalog)
            }
        }
    }

    private var basics: some View {
        VStack(spacing: 14) {
            DatingSectionCard(title: "Пол", systemImage: "person.2") {
                HStack(spacing: 12) {
                    ForEach(catalog?.genders ?? []) { gender in
                        GenderCard(
                            gender: gender,
                            isSelected: genderChosen && form.gender == gender.code
                        ) {
                            form.gender = gender.code
                            genderChosen = true
                        }
                    }
                }
                .sensoryFeedback(.selection, trigger: form.gender)
            }
            DatingSectionCard(title: "Дата рождения", systemImage: "birthday.cake", subtitle: birthDateHint) {
                DatePicker("Дата рождения", selection: $form.birthDate, in: birthDateRange, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .onChange(of: form.birthDate) { birthDateChosen = true }
            }
            DatingSectionCard(title: "Город", systemImage: "mappin.and.ellipse") {
                LocationFields(form: $form, catalog: catalog)
            }
        }
    }

    private var birthDateHint: String {
        guard birthDateChosen else { return "Прокрутите до своей даты рождения. Знакомства доступны с \(DatingLimits.minAge) лет." }
        return "Вам \(RussianPlural.years(age))"
    }

    private var age: Int {
        Calendar.current.dateComponents([.year], from: form.birthDate, to: .now).year ?? 0
    }

    /// Колесо не даёт выбрать дату младше минимального возраста — сервер такую анкету всё равно отклонит.
    private var birthDateRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let latest = calendar.date(byAdding: .year, value: -DatingLimits.minAge, to: .now) ?? .now
        let earliest = calendar.date(byAdding: .year, value: -DatingLimits.maxAge, to: .now) ?? .distantPast
        return earliest...latest
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if step != .basics {
                Button {
                    go(to: step.rawValue - 1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.app(.headline))
                        .frame(width: 54, height: 54)
                        .glassSurface(in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityLabel("Назад")
                .transition(.scale.combined(with: .opacity))
            }
            Button {
                if step == .tastes {
                    onCreate()
                } else {
                    go(to: step.rawValue + 1)
                }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(step == .tastes ? "Создать анкету" : "Далее")
                    if step != .tastes {
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.app(.headline))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(DatingStyle.brandGradient, in: Capsule())
                .shadow(color: DatingStyle.rose.opacity(canContinue ? 0.35 : 0), radius: 12, y: 6)
                .opacity(canContinue ? 1 : 0.45)
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canContinue || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .animation(DatingStyle.spring, value: step)
    }

    private var canContinue: Bool {
        switch step {
        case .basics: genderChosen && birthDateChosen && !form.cityCode.isEmpty
        case .about: form.bio.count <= DatingLimits.maxBioLength
        case .goals, .lifestyle, .tastes: true
        }
    }

    private var stepTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private func go(to rawValue: Int) {
        guard let next = Step(rawValue: rawValue) else { return }
        movingForward = rawValue > step.rawValue
        withAnimation(DatingStyle.spring) { step = next }
    }
}

/// Крупная карточка выбора пола.
private struct GenderCard: View {
    let gender: CatalogItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: gender.code == "FEMALE" ? "figure.stand.dress" : "figure.stand")
                    .font(.system(size: 34))
                    .symbolEffect(.bounce, value: isSelected)
                Text(gender.name)
                    .font(.app(.subheadline, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? AnyShapeStyle(DatingStyle.brandGradient) : AnyShapeStyle(Color.appElevated))
            }
            .scaleEffect(isSelected ? 1.03 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Поля анкеты (общие для мастера и правки)

/// Подпись над группой чипов.
private struct FieldGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.app(.subheadline, weight: .semibold))
                .foregroundStyle(.secondary)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GoalsFields: View {
    @Binding var form: ProfileForm
    let catalog: DatingCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldGroup(title: "Цель знакомства") {
                ChoiceChips(items: catalog?.relationshipGoals ?? [], selection: $form.relationshipGoal)
            }
            FieldGroup(title: "Семейное положение") {
                ChoiceChips(items: catalog?.maritalStatuses ?? [], selection: $form.maritalStatus)
            }
            FieldGroup(title: "Дети") {
                ChoiceChips(items: catalog?.children ?? [], selection: $form.children)
            }
            FieldGroup(title: "Хочу детей") {
                ChoiceChips(items: catalog?.wantsChildren ?? [], selection: $form.wantsChildren)
            }
        }
    }
}

private struct AboutFields: View {
    @Binding var form: ProfileForm

    @FocusState private var bioFocused: Bool

    /// Начала фраз для тех, кто не знает, с чего начать рассказ о себе.
    private static let bioPrompts = [
        "Мои выходные — это…",
        "Я ценю в людях…",
        "Меня легко рассмешить, если…",
        "Мечтаю когда-нибудь…",
        "В семье для меня важно…",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Пара фраз о том, какой вы человек", text: $form.bio, axis: .vertical)
                    .lineLimit(4...10)
                    .focused($bioFocused)
                    .padding(12)
                    .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                HStack {
                    Text("Подсказки")
                        .font(.app(.caption, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(form.bio.count) / \(DatingLimits.maxBioLength)")
                        .font(.app(.caption).monospacedDigit())
                        .foregroundStyle(form.bio.count > DatingLimits.maxBioLength ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                        .contentTransition(.numericText())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Self.bioPrompts, id: \.self) { prompt in
                            SelectableChip(text: prompt, isSelected: false) { insert(prompt) }
                        }
                    }
                }
            }
            FieldGroup(title: "Профессия") {
                TextField("Например, врач или инженер", text: $form.profession)
                    .padding(12)
                    .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HeightPicker(heightCm: $form.heightCm)
        }
    }

    private func insert(_ prompt: String) {
        let trimmed = form.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        // Многоточие убираем: пользователь продолжит фразу сам.
        let start = prompt.replacingOccurrences(of: "…", with: " ")
        form.bio = trimmed.isEmpty ? start : trimmed + "\n" + start
        bioFocused = true
    }
}

private struct LifestyleFields: View {
    @Binding var form: ProfileForm
    let catalog: DatingCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldGroup(title: "Образование") {
                ChoiceChips(items: catalog?.education ?? [], selection: $form.education)
            }
            FieldGroup(title: "Курение") {
                ChoiceChips(items: catalog?.habitFrequencies ?? [], selection: $form.smoking)
            }
            FieldGroup(title: "Алкоголь") {
                ChoiceChips(items: catalog?.habitFrequencies ?? [], selection: $form.alcohol)
            }
            FieldGroup(title: "Спорт") {
                ChoiceChips(items: catalog?.habitFrequencies ?? [], selection: $form.sport)
            }
        }
    }
}

private struct TastesFields: View {
    @Binding var form: ProfileForm
    let catalog: DatingCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            FieldGroup(title: "Интересы") {
                MultiChoiceChips(items: catalog?.interests ?? [], limit: DatingLimits.maxInterests, selection: $form.interests)
            }
            FieldGroup(title: "Занятия") {
                MultiChoiceChips(items: catalog?.hobbies ?? [], limit: DatingLimits.maxHobbies, selection: $form.hobbies)
            }
            FieldGroup(title: "Любимая кухня") {
                MultiChoiceChips(items: catalog?.cuisines ?? [], limit: DatingLimits.maxCuisines, selection: $form.cuisines)
            }
        }
    }
}

/// Страна (если их больше одной) и город чипами: городов в справочнике немного, список целиком виден сразу.
private struct LocationFields: View {
    @Binding var form: ProfileForm
    let catalog: DatingCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let countries = catalog?.countries, countries.count > 1 {
                Picker("Страна", selection: countryBinding) {
                    ForEach(countries) { country in
                        Text(country.name).tag(country.code)
                    }
                }
                .pickerStyle(.segmented)
            }
            ChoiceChips(items: catalog?.cities(in: form.countryCode) ?? [], selection: cityBinding)
        }
    }

    /// Город из другой страны сервер не примет — при смене страны выбор города сбрасываем.
    private var countryBinding: Binding<String> {
        Binding(
            get: { form.countryCode },
            set: { newCode in
                guard newCode != form.countryCode else { return }
                form.countryCode = newCode
                form.cityCode = ""
            }
        )
    }

    /// В форме «город не выбран» — пустая строка, а чипам нужен nil.
    private var cityBinding: Binding<String?> {
        Binding(
            get: { form.cityCode.isEmpty ? nil : form.cityCode },
            set: { form.cityCode = $0 ?? "" }
        )
    }
}

/// «1 год», «3 года», «25 лет».
enum RussianPlural {
    static func years(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        if (11...14).contains(lastTwo) { return "\(count) лет" }
        switch last {
        case 1: return "\(count) год"
        case 2...4: return "\(count) года"
        default: return "\(count) лет"
        }
    }
}

/// Редактируемая копия анкеты: форма правит её, а на сервер уходит одним запросом.
private struct ProfileForm: Equatable {
    var gender = "MALE"
    /// Колесо даты стартует с этого возраста: листать от сегодняшнего дня до нужного года долго.
    private static let initialWheelAge = 25

    var birthDate = Calendar.current.date(byAdding: .year, value: -initialWheelAge, to: .now) ?? .now
    var countryCode = "TJ"
    var cityCode = ""
    var bio = ""
    var interests: [String] = []
    var hobbies: [String] = []
    var cuisines: [String] = []
    var heightCm: Int?
    var education: String?
    var profession = ""
    var relationshipGoal: String?
    var maritalStatus: String?
    var children: String?
    var wantsChildren: String?
    var smoking: String?
    var alcohol: String?
    var sport: String?
    var hidden = false

    init() {}

    init(profile: DatingProfileMine) {
        gender = profile.shared.gender
        birthDate = CalendarDate.date(from: profile.birthDate) ?? Date()
        countryCode = profile.shared.countryCode
        cityCode = profile.shared.cityCode
        bio = profile.shared.bio
        interests = profile.shared.interests
        hobbies = profile.shared.hobbies
        cuisines = profile.shared.cuisines
        heightCm = profile.shared.heightCm
        education = profile.shared.education
        profession = profile.shared.profession ?? ""
        relationshipGoal = profile.shared.relationshipGoal
        maritalStatus = profile.shared.maritalStatus
        children = profile.shared.children
        wantsChildren = profile.shared.wantsChildren
        smoking = profile.shared.smoking
        alcohol = profile.shared.alcohol
        sport = profile.shared.sport
        hidden = profile.hidden
    }

    func update(isCreating: Bool) -> DatingProfileUpdate {
        var update = DatingProfileUpdate()
        // Пол и дата рождения задаются только при создании: у существующей анкеты сервер отклонит их изменение.
        if isCreating {
            update.gender = gender
            update.birthDate = CalendarDate.string(from: birthDate)
        }
        update.countryCode = countryCode
        update.cityCode = cityCode
        update.bio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        update.interests = interests
        update.hobbies = hobbies
        update.cuisines = cuisines
        update.hidden = hidden
        update.heightCm = heightCm
        update.education = education
        update.relationshipGoal = relationshipGoal
        update.maritalStatus = maritalStatus
        update.children = children
        update.wantsChildren = wantsChildren
        update.smoking = smoking
        update.alcohol = alcohol
        update.sport = sport
        let trimmedProfession = profession.trimmingCharacters(in: .whitespacesAndNewlines)
        update.profession = trimmedProfession.isEmpty ? nil : trimmedProfession
        update.clearing = DatingProfileUpdate.allNullableKeys
        return update
    }
}

/// Предпросмотр: своя анкета ровно в том виде, в каком её видят другие.
struct DatingProfilePreviewView: View {
    let catalog: DatingCatalog?

    @State private var profile: DatingProfilePublic?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let profile {
                DatingProfileDetailView(profile: profile, catalog: catalog, showsModeration: false)
            } else if let errorMessage {
                ContentUnavailableView("Не удалось показать анкету", systemImage: "eye.slash", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                profile = try await APIClient.shared.fetchMyDatingPreview()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
