import SwiftUI

/// Правила сообщества: без их принятия сервер закрывает все запросы знакомств.
struct CommunityRulesView: View {
    let rules: CommunityRules
    let onAccept: () async -> Void

    @State private var isAccepting = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Правила сообщества")
                    .font(.app(.title2, weight: .bold))
                Text("Знакомства работают, пока все соблюдают эти правила. Нарушения проверяют модераторы.")
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)

                ForEach(Array(rules.rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(index + 1).")
                            .font(.app(.subheadline).monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(rule)
                            .font(.app(.subheadline))
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                isAccepting = true
                Task {
                    await onAccept()
                    isAccepting = false
                }
            } label: {
                if isAccepting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Принимаю")
                        .frame(maxWidth: .infinity)
                }
            }
            .glassProminentButtonStyle()
            .controlSize(.large)
            .disabled(isAccepting)
            .padding(20)
        }
    }
}
