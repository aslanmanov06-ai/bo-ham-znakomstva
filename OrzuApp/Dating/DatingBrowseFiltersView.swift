import SwiftUI

/// Фильтры сетки анкет. Правится черновик: сетка перезагружается один раз по «Показать», а не на каждый шаг степпера.
struct DatingBrowseFiltersView: View {
    let catalog: DatingCatalog?
    /// Города — из страны своей анкеты: сетка показывает анкеты только этой страны.
    let countryCode: String?
    let onApply: (DatingBrowseFilters) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var filters: DatingBrowseFilters

    init(filters: DatingBrowseFilters, catalog: DatingCatalog?, countryCode: String?, onApply: @escaping (DatingBrowseFilters) -> Void) {
        self.catalog = catalog
        self.countryCode = countryCode
        self.onApply = onApply
        _filters = State(initialValue: filters)
    }

    var body: some View {
        Form {
            Section {
                Picker("Город", selection: $filters.cityCode) {
                    Text("Любой").tag(String?.none)
                    ForEach(catalog?.cities(in: countryCode ?? "") ?? []) { city in
                        Text(city.name).tag(String?.some(city.code))
                    }
                }
            } header: {
                Label("Город", systemImage: "mappin.and.ellipse")
            }

            Section {
                optionalNumber(title: "От", unit: "лет", value: $filters.ageMin, range: DatingLimits.minAge...(filters.ageMax ?? DatingLimits.maxAge), defaultValue: 20)
                optionalNumber(title: "До", unit: "лет", value: $filters.ageMax, range: (filters.ageMin ?? DatingLimits.minAge)...DatingLimits.maxAge, defaultValue: 35)
            } header: {
                Label("Возраст", systemImage: "person.2")
            }

            Section {
                optionalNumber(title: "От", unit: "см", value: $filters.heightMin, range: DatingLimits.minHeightCm...(filters.heightMax ?? DatingLimits.maxHeightCm), defaultValue: 160)
                optionalNumber(title: "До", unit: "см", value: $filters.heightMax, range: (filters.heightMin ?? DatingLimits.minHeightCm)...DatingLimits.maxHeightCm, defaultValue: 190)
            } header: {
                Label("Рост", systemImage: "ruler")
            }

            Section {
                multiSelect(items: catalog?.relationshipGoals ?? [], selection: $filters.relationshipGoals)
            } header: {
                Label("Цель знакомства", systemImage: "heart")
            }

            Section {
                multiSelect(items: catalog?.maritalStatuses ?? [], selection: $filters.maritalStatuses)
            } header: {
                Label("Семейное положение", systemImage: "figure.2")
            }

            Section {
                Picker("Есть дети", selection: $filters.children) {
                    Text("Не важно").tag(String?.none)
                    ForEach(catalog?.children ?? []) { item in
                        Text(item.name).tag(String?.some(item.code))
                    }
                }
                multiSelect(items: catalog?.wantsChildren ?? [], selection: $filters.wantsChildren, title: "Хочет детей")
            } header: {
                Label("Дети", systemImage: "figure.and.child.holdinghands")
            }

            Section {
                multiSelect(items: catalog?.education ?? [], selection: $filters.education)
            } header: {
                Label("Образование", systemImage: "graduationcap")
            }

            Section {
                multiSelect(items: catalog?.interests ?? [], selection: $filters.interests, limit: DatingLimits.maxInterests)
            } header: {
                Label("Интересы", systemImage: "sparkles")
            }
        }
        .appScreenBackground()
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

    /// Числовой фильтр, который можно выключить: выключенный не отправляется на сервер — «не важно».
    private func optionalNumber(
        title: String,
        unit: String,
        value: Binding<Int?>,
        range: ClosedRange<Int>,
        defaultValue: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue != nil },
                // Значение по умолчанию прижимаем к допустимому: «от» не должно оказаться больше уже заданного «до».
                set: { value.wrappedValue = $0 ? min(max(defaultValue, range.lowerBound), range.upperBound) : nil }
            ))
            if let current = value.wrappedValue {
                Stepper("\(current) \(unit)", value: Binding(
                    get: { current },
                    set: { value.wrappedValue = $0 }
                ), in: range)
            }
        }
    }

    /// limit — сколько можно выбрать (сервер больше не примет); nil — без ограничения.
    @ViewBuilder
    private func multiSelect(items: [CatalogItem], selection: Binding<[String]>, title: String? = nil, limit: Int? = nil) -> some View {
        if let title {
            Text(title)
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
        }
        ForEach(items) { item in
            let isSelected = selection.wrappedValue.contains(item.code)
            Button {
                toggle(item.code, in: selection)
            } label: {
                HStack {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.tint)
                    }
                }
            }
            .disabled(!isSelected && limit.map { selection.wrappedValue.count >= $0 } == true)
        }
    }

    private func toggle(_ code: String, in selection: Binding<[String]>) {
        if let index = selection.wrappedValue.firstIndex(of: code) {
            selection.wrappedValue.remove(at: index)
        } else {
            selection.wrappedValue.append(code)
        }
    }
}
