import SwiftUI

/// Фильтры сетки анкет (макет «Анкеты — фильтр»): карточки с чипами и ползунками. Правится черновик — сетка
/// перезагружается один раз по «Показать». Только для этого списка: «Кого ищу» от них не меняется.
struct DatingBrowseFiltersView: View {
    let catalog: DatingCatalog?
    /// Города — из страны своей анкеты: сетка показывает анкеты только этой страны.
    let countryCode: String?
    /// Пол по умолчанию — тот, что в «Кого ищу».
    let lookingFor: String?
    let onApply: (DatingBrowseFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filters: DatingBrowseFilters

    /// Шаги расстояния; последний — «любое».
    private static let distanceSteps = [5, 10, 25, 50, 100, 200, 500]

    init(filters: DatingBrowseFilters, catalog: DatingCatalog?, countryCode: String?, lookingFor: String?, onApply: @escaping (DatingBrowseFilters) -> Void) {
        self.catalog = catalog
        self.countryCode = countryCode
        self.lookingFor = lookingFor
        self.onApply = onApply
        _filters = State(initialValue: filters)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Фильтры только для этого списка — ваша анкета «Кого ищу» от них не меняется.")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                DatingSectionCard(title: String(localized: "Пол"), systemImage: "person.2") {
                    genderPicker
                }
                cityCard
                DatingSectionCard(
                    title: String(localized: "Расстояние"),
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    subtitle: String(localized: "Нужна геопозиция — без неё фильтр не сработает.")
                ) {
                    distanceSlider
                }
                DatingSectionCard(title: String(localized: "Возраст"), systemImage: "person.crop.circle") {
                    optionalRange(
                        lower: $filters.ageMin, upper: $filters.ageMax, bounds: DatingLimits.minAge...DatingLimits.maxAge,
                        text: { "\($0)–\(RussianPlural.years($1))" }
                    )
                }
                chipsCard(String(localized: "Семейное положение"), systemImage: "heart.circle", items: catalog?.maritalStatuses ?? [], selection: $filters.maritalStatuses)
                DatingSectionCard(title: String(localized: "Дети"), systemImage: "figure.and.child.holdinghands") {
                    FlowLayout(spacing: 8) {
                        SelectableChip(text: String(localized: "Не важно"), isSelected: filters.children == nil) { filters.children = nil }
                        SelectableChip(text: String(localized: "Без детей"), isSelected: filters.children == "NONE") { filters.children = "NONE" }
                        SelectableChip(text: String(localized: "С детьми"), isSelected: filters.children == "HAS") { filters.children = "HAS" }
                    }
                }
                DatingSectionCard(title: String(localized: "Рост"), systemImage: "ruler") {
                    optionalRange(
                        lower: $filters.heightMin, upper: $filters.heightMax, bounds: DatingLimits.minHeightCm...DatingLimits.maxHeightCm,
                        text: { String(localized: "\($0)–\($1) см") }
                    )
                }
                chipsCard(String(localized: "Курение"), systemImage: "smoke", items: habits(smoking: true), selection: $filters.smoking)
                chipsCard(String(localized: "Алкоголь"), systemImage: "wineglass", items: habits(smoking: false), selection: $filters.alcohol)
                chipsCard(String(localized: "Цель знакомства"), systemImage: "heart", items: catalog?.relationshipGoals ?? [], selection: $filters.relationshipGoals)
                chipsCard(String(localized: "Хочет детей"), systemImage: "house", items: catalog?.wantsChildren ?? [], selection: $filters.wantsChildren)
                chipsCard(String(localized: "Образование"), systemImage: "graduationcap", items: catalog?.education ?? [], selection: $filters.education)
                DatingSectionCard(title: String(localized: "Интересы"), systemImage: "sparkles") {
                    MultiChoiceChips(items: catalog?.interests ?? [], limit: DatingLimits.maxInterests, selection: $filters.interests)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(DatingBackdrop())
        .navigationTitle("Фильтры")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сбросить") { filters = DatingBrowseFilters() }
                    .disabled(filters == DatingBrowseFilters())
            }
        }
        // Главное действие — крупной кнопкой у большого пальца, а не мелким словом в углу.
        .safeAreaInset(edge: .bottom) {
            Button("Показать") {
                onApply(filters)
                dismiss()
            }
            .buttonStyle(.appPrimary)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private var genderPicker: some View {
        let selected = filters.gender ?? lookingFor
        return HStack(spacing: 4) {
            ForEach([("FEMALE", String(localized: "Девушки")), ("MALE", String(localized: "Парни"))], id: \.0) { code, title in
                let isOn = selected == code
                Button {
                    // Пол из «Кого ищу» не отправляем: сервер и так подставит его по умолчанию.
                    filters.gender = code == lookingFor ? nil : code
                } label: {
                    Text(title)
                        .font(.app(.subheadline, weight: isOn ? .bold : .medium))
                        .foregroundStyle(isOn ? Color.appBackground : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(isOn ? Color.primary : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var cityCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
                .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text("Город").font(.app(.headline))
            Spacer()
            Picker("Город", selection: $filters.cityCode) {
                Text("Любой").tag(String?.none)
                ForEach(catalog?.cities(in: countryCode ?? "") ?? []) { city in
                    Text(city.name).tag(String?.some(city.code))
                }
            }
            .labelsHidden()
            .tint(Color.brand)
        }
        .padding(16)
        .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
    }

    /// Ползунок по шагам; крайний правый — «любое» (фильтр не отправляется).
    private var distanceSlider: some View {
        let steps = Self.distanceSteps
        let index = Binding<Double>(
            get: { Double(filters.maxDistanceKm.flatMap { steps.firstIndex(of: $0) } ?? steps.count) },
            set: { value in
                let step = Int(value.rounded())
                filters.maxDistanceKm = step < steps.count ? steps[step] : nil
            }
        )
        return VStack(alignment: .leading, spacing: 6) {
            Text(filters.maxDistanceKm.map { String(localized: "до \($0) км") } ?? String(localized: "Любое"))
                .font(.app(.subheadline, weight: .semibold))
            Slider(value: index, in: 0...Double(steps.count), step: 1)
                .tint(Color.brand)
        }
    }

    /// Диапазон, который можно не задавать: бегунки на краях — «не важно», такой фильтр не отправляется.
    private func optionalRange(lower: Binding<Int?>, upper: Binding<Int?>, bounds: ClosedRange<Int>, text: @escaping (Int, Int) -> String) -> some View {
        let low = Binding<Int>(
            get: { lower.wrappedValue ?? bounds.lowerBound },
            set: { lower.wrappedValue = $0 == bounds.lowerBound ? nil : $0 }
        )
        let high = Binding<Int>(
            get: { upper.wrappedValue ?? bounds.upperBound },
            set: { upper.wrappedValue = $0 == bounds.upperBound ? nil : $0 }
        )
        let isAny = lower.wrappedValue == nil && upper.wrappedValue == nil
        return VStack(alignment: .leading, spacing: 6) {
            Text(isAny ? String(localized: "Не важно") : text(low.wrappedValue, high.wrappedValue))
                .font(.app(.subheadline, weight: .semibold))
            RangeSlider(lower: low, upper: high, bounds: bounds)
        }
    }

    private func chipsCard(_ title: String, systemImage: String, items: [CatalogItem], selection: Binding<[String]>) -> some View {
        DatingSectionCard(title: title, systemImage: systemImage) {
            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    SelectableChip(text: item.name, isSelected: selection.wrappedValue.contains(item.code)) {
                        if let index = selection.wrappedValue.firstIndex(of: item.code) {
                            selection.wrappedValue.remove(at: index)
                        } else {
                            selection.wrappedValue.append(item.code)
                        }
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: selection.wrappedValue)
        }
    }

    /// «Не курит / Иногда / Часто» вместо «Никогда / Иногда / Часто» — так понятнее, о ком речь.
    private func habits(smoking: Bool) -> [CatalogItem] {
        (catalog?.habitFrequencies ?? []).map { item in
            guard item.code == "NEVER" else { return item }
            return CatalogItem(code: item.code, name: smoking ? String(localized: "Не курит") : String(localized: "Не пьёт"))
        }
    }
}
