import SwiftUI

/// Анкета «Кого ищу» (макет «Регистрация — „Кого вы ищете“»): пол, возраст, дети, семейное положение и города.
/// Критерии видны в анкете; в «Знакомствах» — только взаимно подходящие. На фильтр сетки анкет не влияет.
/// isOnboarding — шаг сразу после создания своей анкеты; иначе открыт из профиля.
struct SearchCriteriaView: View {
    @ObservedObject var dating: DatingViewModel
    var isOnboarding = false
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var lookingFor = "FEMALE"
    @State private var ageMin = 22
    @State private var ageMax = 30
    @State private var children: String?
    @State private var maritalStatuses: [String] = []
    @State private var cityCodes: [String] = []
    @State private var showAllCities = false
    @State private var loaded = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// Сколько городов видно до «Ещё…»: остальные — по нажатию, выбранные видны всегда.
    private static let visibleCities = 4

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                if loaded {
                    DatingSectionCard(title: String(localized: "Ищу"), systemImage: "person.2") {
                        genderPicker
                    }
                    DatingSectionCard(title: String(localized: "Возраст"), systemImage: "person.crop.circle") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(ageMin)–\(RussianPlural.years(ageMax))")
                                .font(.app(.subheadline, weight: .semibold))
                            RangeSlider(lower: $ageMin, upper: $ageMax, bounds: DatingLimits.minAge...DatingLimits.maxAge)
                        }
                    }
                    DatingSectionCard(title: String(localized: "Дети"), systemImage: "figure.and.child.holdinghands") {
                        FlowLayout(spacing: 8) {
                            SelectableChip(text: String(localized: "Не важно"), isSelected: children == nil) { children = nil }
                            SelectableChip(text: String(localized: "Без детей"), isSelected: children == "NONE") { children = "NONE" }
                            SelectableChip(text: String(localized: "С детьми"), isSelected: children == "HAS") { children = "HAS" }
                        }
                    }
                    DatingSectionCard(
                        title: String(localized: "Семейное положение"),
                        systemImage: "heart.circle",
                        subtitle: String(localized: "Можно выбрать несколько. Ничего не выбрано — не важно.")
                    ) {
                        FlowLayout(spacing: 8) {
                            ForEach(dating.catalog?.maritalStatuses ?? []) { item in
                                SelectableChip(text: CriteriaText.maritalStatus(item, lookingFor: lookingFor), isSelected: maritalStatuses.contains(item.code)) {
                                    toggle(item.code, in: &maritalStatuses)
                                }
                            }
                        }
                    }
                    DatingSectionCard(
                        title: String(localized: "Город"),
                        systemImage: "mappin.and.ellipse",
                        subtitle: String(localized: "Ничего не выбрано — любой город.")
                    ) {
                        cityChips
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: [children ?? ""] + maritalStatuses + cityCodes)
        }
        .background(DatingBackdrop())
        .safeAreaInset(edge: .bottom) {
            Button(isOnboarding ? String(localized: "Готово") : String(localized: "Сохранить")) { save() }
                .buttonStyle(.appPrimary)
                .disabled(!loaded || isSaving)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
        }
        .navigationTitle(isOnboarding ? "" : String(localized: "Кого ищу"))
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.selection, trigger: [children ?? ""] + maritalStatuses + cityCodes)
        .task { await load() }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var header: some View {
        if isOnboarding {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Capsule().fill(DatingStyle.brandGradient).frame(height: 4)
                    Capsule().fill(DatingStyle.brandGradient).frame(height: 4)
                }
                .padding(.bottom, 8)
                Text("Шаг 2 из 2")
                    .font(.app(.footnote, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("Кого вы ищете")
                    .font(.display(.title))
                Text("Это увидят в вашей анкете. В «Знакомствах» покажем тех, кто подходит вам и кому подходите вы.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        } else {
            Text("Это видно в вашей анкете. В «Знакомствах» — только те, кто подходит вам и кому подходите вы. На фильтры в «Анкетах» не влияет.")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var genderPicker: some View {
        HStack(spacing: 4) {
            segment(String(localized: "Девушку"), code: "FEMALE")
            segment(String(localized: "Парня"), code: "MALE")
        }
        .padding(4)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private func segment(_ title: String, code: String) -> some View {
        let selected = lookingFor == code
        return Button { lookingFor = code } label: {
            Text(title)
                .font(.app(.subheadline, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Color.appBackground : Color.secondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(selected ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var cityChips: some View {
        let cities = myCountryCities
        let shown = showAllCities ? cities : cities.enumerated().filter { $0.offset < Self.visibleCities || cityCodes.contains($0.element.code) }.map(\.element)
        return FlowLayout(spacing: 8) {
            ForEach(shown) { city in
                SelectableChip(text: city.name, isSelected: cityCodes.contains(city.code)) {
                    toggle(city.code, in: &cityCodes)
                }
            }
            if !showAllCities && shown.count < cities.count {
                SelectableChip(text: String(localized: "Ещё…"), isSelected: false) { showAllCities = true }
            }
        }
    }

    /// Города страны своей анкеты: знакомства — внутри одной страны.
    private var myCountryCities: [CatalogItem] {
        let countries = dating.catalog?.countries ?? []
        let country = countries.first { $0.code == dating.profile?.shared.countryCode } ?? countries.first
        return country?.cities ?? []
    }

    private func toggle(_ code: String, in list: inout [String]) {
        if let index = list.firstIndex(of: code) {
            list.remove(at: index)
        } else {
            list.append(code)
        }
    }

    private func load() async {
        guard !loaded else { return }
        do {
            if dating.criteria == nil { try await dating.loadCriteria() }
            if let criteria = dating.criteria {
                lookingFor = criteria.lookingFor
                ageMin = criteria.ageMin
                ageMax = criteria.ageMax
                children = criteria.children
                maritalStatuses = criteria.maritalStatuses
                cityCodes = criteria.cityCodes
            }
            loaded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        isSaving = true
        let update = SearchCriteriaUpdate(lookingFor: lookingFor, ageMin: ageMin, ageMax: ageMax, children: children, cityCodes: cityCodes, maritalStatuses: maritalStatuses)
        Task {
            defer { isSaving = false }
            do {
                try await dating.saveCriteria(update)
                onDone()
                if !isOnboarding { dismiss() }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Подписи «Кого ищу»: семейное положение — в роде того, кого ищут («Не была замужем» / «Не был женат»).
enum CriteriaText {
    static func maritalStatus(_ item: CatalogItem, lookingFor: String) -> String {
        let female = lookingFor == "FEMALE"
        switch item.code {
        case "NEVER_MARRIED": return female ? String(localized: "Не была замужем") : String(localized: "Не был женат")
        case "DIVORCED": return String(localized: "В разводе")
        case "WIDOWED": return female ? String(localized: "Вдова") : String(localized: "Вдовец")
        default: return item.name
        }
    }

    static func children(_ code: String?) -> String {
        switch code {
        case "NONE": String(localized: "Без детей")
        case "HAS": String(localized: "С детьми")
        default: String(localized: "Не важно")
        }
    }

    static func lookingFor(_ code: String) -> String {
        code == "FEMALE" ? String(localized: "Девушку") : String(localized: "Парня")
    }
}

/// Ползунок диапазона с двумя бегунками: «от» не заходит за «до».
struct RangeSlider: View {
    @Binding var lower: Int
    @Binding var upper: Int
    let bounds: ClosedRange<Int>

    private let thumb: CGFloat = 24

    var body: some View {
        GeometryReader { geometry in
            let track = max(geometry.size.width - thumb, 1)
            let lowerX = position(lower, track: track)
            let upperX = position(upper, track: track)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.appElevated)
                    .frame(height: 4)
                    .padding(.horizontal, thumb / 2)
                Capsule()
                    .fill(DatingStyle.brandGradient)
                    .frame(width: max(upperX - lowerX, 0), height: 4)
                    .offset(x: lowerX + thumb / 2)
                handle(value: $lower, x: lowerX, track: track, range: bounds.lowerBound...upper, label: String(localized: "Возраст от"))
                handle(value: $upper, x: upperX, track: track, range: lower...bounds.upperBound, label: String(localized: "Возраст до"))
            }
            .coordinateSpace(name: "range")
        }
        .frame(height: 28)
        .sensoryFeedback(.selection, trigger: lower)
        .sensoryFeedback(.selection, trigger: upper)
    }

    private func handle(value: Binding<Int>, x: CGFloat, track: CGFloat, range: ClosedRange<Int>, label: String) -> some View {
        Circle()
            .fill(Color.white)
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.3), radius: 3, y: 2)
            .offset(x: x)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("range"))
                    .onChanged { drag in
                        let fraction = (drag.location.x - thumb / 2) / track
                        let raw = bounds.lowerBound + Int((fraction * CGFloat(bounds.count - 1)).rounded())
                        value.wrappedValue = min(max(raw, range.lowerBound), range.upperBound)
                    }
            )
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue("\(value.wrappedValue)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value.wrappedValue = min(value.wrappedValue + 1, range.upperBound)
                case .decrement: value.wrappedValue = max(value.wrappedValue - 1, range.lowerBound)
                @unknown default: break
                }
            }
    }

    private func position(_ value: Int, track: CGFloat) -> CGFloat {
        CGFloat(value - bounds.lowerBound) / CGFloat(max(bounds.count - 1, 1)) * track
    }
}

/// «Кого ищет» в чужой анкете (макеты «Чужая анкета — вы подходите / не подходите»): критерии по пунктам
/// с ✓ или ✗ для меня и общий итог. viewer — моя анкета; без неё отметок по пунктам нет, только итог с сервера.
struct SearchCriteriaCard: View {
    let criteria: SearchCriteria
    let fits: Bool?
    let viewer: DatingProfilePublic?
    let catalog: DatingCatalog?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label {
                    Text("Кого ищет").font(.app(.headline))
                } icon: {
                    Image(systemName: "heart")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 30, height: 30)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Spacer(minLength: 8)
                if let fits {
                    verdict(fits)
                }
            }
            .padding(.bottom, 12)
            row(String(localized: "Ищет"), CriteriaText.lookingFor(criteria.lookingFor), fits: viewer.map { $0.gender == criteria.lookingFor })
            row(String(localized: "Возраст"), "\(criteria.ageMin)–\(criteria.ageMax)", fits: viewer.map { criteria.fitsAge($0.age) })
            row(String(localized: "Дети"), CriteriaText.children(criteria.children), fits: viewer.map { criteria.fitsChildren($0.children) })
            row(String(localized: "Семейное положение"), maritalText, fits: viewer.map { criteria.fitsMaritalStatus($0.maritalStatus) })
            row(String(localized: "Город"), cityText, fits: viewer.map { criteria.fitsCity($0.cityCode) })
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
        .accessibilityElement(children: .combine)
    }

    /// Итог: подхожу или нет, а если нет — по какому пункту (первому несовпавшему).
    private func verdict(_ fits: Bool) -> some View {
        let text = fits ? String(localized: "Вы подходите") : mismatchText
        let tint = fits ? Color.criteriaFits : Color.brand
        return Label(text, systemImage: fits ? "checkmark" : "xmark")
            .font(.app(.caption, weight: .bold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    private var mismatchText: String {
        guard let viewer else { return String(localized: "Вы не подходите") }
        if !criteria.fitsAge(viewer.age) { return String(localized: "Вы не подходите по возрасту") }
        if !criteria.fitsCity(viewer.cityCode) { return String(localized: "Вы не подходите по городу") }
        if !criteria.fitsChildren(viewer.children) { return String(localized: "Вы не подходите: дети") }
        if !criteria.fitsMaritalStatus(viewer.maritalStatus) { return String(localized: "Вы не подходите: семейное положение") }
        return String(localized: "Вы не подходите")
    }

    private var maritalText: String {
        guard !criteria.maritalStatuses.isEmpty else { return String(localized: "Не важно") }
        let items = catalog?.maritalStatuses ?? []
        return criteria.maritalStatuses
            .map { code in items.first { $0.code == code }.map { CriteriaText.maritalStatus($0, lookingFor: criteria.lookingFor) } ?? code }
            .joined(separator: ", ")
    }

    private var cityText: String {
        guard !criteria.cityCodes.isEmpty else { return String(localized: "Любой") }
        let cities = catalog?.countries.flatMap(\.cities) ?? []
        return criteria.cityCodes.map { code in cities.first { $0.code == code }?.name ?? code }.joined(separator: ", ")
    }

    private func row(_ title: String, _ value: String, fits: Bool?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.app(.subheadline, weight: .semibold))
                .multilineTextAlignment(.trailing)
            if let fits {
                Image(systemName: fits ? "checkmark" : "xmark")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(fits ? Color.criteriaFits : Color.brand)
                    .accessibilityLabel(fits ? String(localized: "подходит") : String(localized: "не подходит"))
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.appLine).frame(height: 1) }
    }
}

private extension Color {
    /// «Подходит» — зелёный, как онлайн-счётчик рулетки.
    static let criteriaFits = Color(light: 0x1F7A47, dark: 0x7FD8A4)
}
