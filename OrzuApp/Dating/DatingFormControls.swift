import SwiftUI

/// Карточка раздела на экранах знакомств: заголовок с иконкой, пояснение и содержимое.
struct DatingSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Label {
                    Text(title).font(.app(.headline))
                } icon: {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 30, height: 30)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
    }
}

/// Один вариант из справочника: вместо выпадающего списка все варианты видны сразу и выбираются одним касанием.
/// Повторное касание снимает выбор — поле необязательное.
struct ChoiceChips: View {
    let items: [CatalogItem]
    @Binding var selection: String?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items) { item in
                SelectableChip(text: item.name, isSelected: selection == item.code) {
                    selection = selection == item.code ? nil : item.code
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
    }
}

/// Несколько вариантов с лимитом: при попытке выбрать лишний чип счётчик вздрагивает, а телефон коротко вибрирует.
struct MultiChoiceChips: View {
    let items: [CatalogItem]
    let limit: Int
    @Binding var selection: [String]

    @State private var limitHits = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FlowLayout(spacing: 8) {
                ForEach(items) { item in
                    SelectableChip(
                        text: item.name,
                        isSelected: selection.contains(item.code),
                        isDimmed: !selection.contains(item.code) && selection.count >= limit
                    ) {
                        toggle(item.code)
                    }
                }
            }
            Text("Выбрано \(selection.count) из \(limit)")
                .font(.app(.caption, weight: .medium))
                .foregroundStyle(selection.count >= limit ? AnyShapeStyle(DatingStyle.rose) : AnyShapeStyle(.secondary))
                .contentTransition(.numericText())
                .phaseAnimator([0, 1], trigger: limitHits) { content, phase in
                    content.offset(x: phase == 1 ? 6 : 0)
                } animation: { _ in
                    .spring(response: 0.12, dampingFraction: 0.3)
                }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.warning, trigger: limitHits)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: selection)
    }

    private func toggle(_ code: String) {
        if let index = selection.firstIndex(of: code) {
            selection.remove(at: index)
        } else if selection.count < limit {
            selection.append(code)
        } else {
            limitHits += 1
        }
    }
}

/// Чип с выбором: выбранный — в фирменном градиенте с галочкой.
struct SelectableChip: View {
    let text: String
    let isSelected: Bool
    var isDimmed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.app(.caption, weight: .bold))
                        .transition(.scale.combined(with: .opacity))
                }
                Text(text)
                    .lineLimit(1)
            }
            .font(.app(.subheadline, weight: isSelected ? .semibold : .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background {
                if isSelected {
                    Capsule().fill(DatingStyle.brandGradient)
                } else {
                    Capsule().fill(Color.appElevated)
                }
            }
            .opacity(isDimmed ? 0.45 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Рост: ползунок вместо степпера — от 120 до 230 см степпером пришлось бы нажимать десятки раз.
struct HeightPicker: View {
    @Binding var heightCm: Int?

    private let defaultHeightCm = 170

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Рост")
                Spacer()
                if let heightCm {
                    Text("\(heightCm) см")
                        .font(.app(.body, weight: .semibold).monospacedDigit())
                        .foregroundStyle(DatingStyle.rose)
                        .contentTransition(.numericText())
                    Button("Убрать", systemImage: "xmark.circle.fill") { self.heightCm = nil }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                } else {
                    Button("Указать") { heightCm = defaultHeightCm }
                        .font(.app(.subheadline, weight: .semibold))
                        .tint(DatingStyle.rose)
                }
            }
            if let heightCm {
                Slider(
                    value: Binding(
                        get: { Double(heightCm) },
                        set: { self.heightCm = Int($0.rounded()) }
                    ),
                    in: Double(DatingLimits.minHeightCm)...Double(DatingLimits.maxHeightCm),
                    step: 1
                )
                .tint(DatingStyle.rose)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: heightCm == nil)
        .sensoryFeedback(.selection, trigger: heightCm)
    }
}

/// Насколько заполнена анкета: кольцо и подсказки, что добавить, — чтобы процент рос осмысленно.
struct CompletenessCard: View {
    let completeness: ProfileCompleteness

    private let visibleHints = 4

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            CompatibilityRing(score: completeness.percent, size: 64, lineWidth: 7, trackColor: DatingStyle.rose.opacity(0.15))
                .accessibilityLabel("Анкета заполнена на \(completeness.percent) процентов")
            VStack(alignment: .leading, spacing: 6) {
                Text(completeness.missing.isEmpty ? "Анкета заполнена полностью" : "Анкета заполнена на \(completeness.percent)%")
                    .font(.app(.headline))
                if completeness.missing.isEmpty {
                    Text("Совместимость считается по всем полям — теперь она максимально точная.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Добавьте: " + hints.joined(separator: ", "))
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)
    }

    private var hints: [String] {
        Array(completeness.missing.compactMap { Self.missingFieldNames[$0] }.prefix(visibleHints))
    }

    /// Ключи — из completeness.missing на backend (COMPLETENESS_CHECKS в dating-profile.service.ts).
    private static let missingFieldNames: [String: String] = [
        "photos": "фото",
        "video": "видео о себе",
        "bio": "рассказ о себе",
        "heightCm": "рост",
        "interests": "интересы",
        "education": "образование",
        "profession": "профессию",
        "relationshipGoal": "цель знакомства",
        "maritalStatus": "семейное положение",
        "children": "есть ли дети",
        "wantsChildren": "хотите ли детей",
        "habits": "привычки",
        "cuisines": "любимую кухню",
        "hobbies": "занятия",
    ]
}
