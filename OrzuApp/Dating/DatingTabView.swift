import SwiftUI

/// Корень вкладки «Знакомства»: правила сообщества → анкета → лента подходящих анкет.
struct DatingTabView: View {
    @ObservedObject var dating: DatingViewModel
    @StateObject private var matches = MatchesViewModel()

    var body: some View {
        DatingGate(dating: dating, title: "Знакомства") {
            DatingFeedView(dating: dating, matches: matches)
        }
        .task(id: dating.stage) {
            guard dating.stage == .ready else { return }
            await matches.load()
        }
    }
}

/// Общий вход во вкладки знакомств («Знакомства» и «Анкеты»): пока не приняты правила или нет анкеты,
/// вместо содержимого — они. Модель dating общая, поэтому правила, принятые в одной вкладке, открывают обе.
struct DatingGate<Content: View>: View {
    @ObservedObject var dating: DatingViewModel
    let title: String
    @ViewBuilder let content: () -> Content

    @State private var showProfileEditor = false

    var body: some View {
        NavigationStack {
            Group {
                switch dating.stage {
                case .loading:
                    ProgressView()
                        .tint(DatingStyle.rose)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .rules(let rules):
                    CommunityRulesView(rules: rules) {
                        await dating.acceptRules(version: rules.version)
                    }
                case .noProfile:
                    DatingWelcomeView { showProfileEditor = true }
                case .ready:
                    content()
                }
            }
            .navigationTitle(title)
        }
        .task { await dating.load() }
        .sheet(isPresented: $showProfileEditor) {
            NavigationStack {
                DatingProfileEditorView(dating: dating)
            }
        }
        .alert("Ошибка", isPresented: .constant(dating.errorMessage != nil)) {
            // Не загрузились справочник или анкета — без повтора вкладка осталась бы с пустым экраном.
            Button("Повторить") {
                dating.errorMessage = nil
                Task { await dating.load() }
            }
            Button("Ок", role: .cancel) { dating.errorMessage = nil }
        } message: {
            Text(dating.errorMessage ?? "")
        }
    }
}

/// Первый экран для тех, у кого ещё нет анкеты знакомств.
private struct DatingWelcomeView: View {
    let onStart: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            DatingBackdrop()
            FloatingHeartsView(count: 12, colors: [DatingStyle.rose.opacity(0.6), DatingStyle.coral.opacity(0.6)])

            VStack(spacing: 28) {
                Spacer()
                ZStack {
                    PulseRings()
                        .frame(width: 110, height: 110)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 110, height: 110)
                        .background(DatingStyle.brandGradient, in: Circle())
                        .shadow(color: DatingStyle.rose.opacity(0.4), radius: 20, y: 10)
                        .symbolEffect(.bounce, value: appeared)
                }
                .frame(height: 200)

                VStack(spacing: 10) {
                    Text("Знакомства для серьёзных отношений")
                        .font(.display(.title))
                        .multilineTextAlignment(.center)
                    Text("Заполните анкету, подтвердите её селфи — и вы появитесь в ленте у тех, кто ищет такого человека, как вы.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feature("checkmark.seal.fill", "Проверка по селфи", "Каждое селфи сверяет модератор")
                    feature("sparkles", "Совместимость по ценностям", "Подсказываем, что у вас общего")
                    feature("signpost.right.fill", "Путь к браку", "От первого сообщения до никаха")
                }
                .padding(18)
                .appCard(cornerRadius: DatingStyle.tileCornerRadius, padding: nil)

                Spacer()

                Button(action: onStart) {
                    Text("Заполнить анкету")
                        .font(.app(.headline))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(DatingStyle.brandGradient, in: Capsule())
                        .shadow(color: DatingStyle.rose.opacity(0.35), radius: 14, y: 6)
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(24)
            .offset(y: appeared ? 0 : 30)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) { appeared = true }
        }
    }

    private func feature(_ systemImage: String, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.app(.title3))
                .foregroundStyle(DatingStyle.brandGradient)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                Text(subtitle)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
