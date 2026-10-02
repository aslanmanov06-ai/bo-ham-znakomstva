import SwiftUI

/// Переписка в рулетке (макет «Переписка»): анонимный собеседник, только текст, внизу «Стоп», «Нравится», «Далее».
struct RouletteTextChatView: View {
    @ObservedObject var roulette: RouletteViewModel
    let session: RouletteViewModel.Session
    let places: RoulettePlaces

    @State private var draft = ""
    @FocusState private var isInputFocused: Bool
    /// Карточка «Случайный вопрос»: сама — пока никто не написал, потом — по кнопке с лампочкой.
    @State private var icebreaker: String?
    @State private var icebreakerDismissed = false

    private static let bottomId = "bottom"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.appLine)
            messages
            actions
            input
        }
        .background(AppBackground())
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("?")
                .font(.display(size: 17))
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.appElevated, in: Circle())
                .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(session.peer.title)
                        .font(.app(.callout, weight: .semibold))
                    Text("· \(places.city(session.peer.cityCode))")
                        .font(.app(.callout))
                        .foregroundStyle(.secondary)
                    if session.peer.verified { VerifiedBadge().font(.system(size: 14)) }
                }
                .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(roulette.isPeerTyping ? String(localized: "печатает…") : String(localized: "анонимно"))
                        .font(.app(.footnote))
                        .foregroundStyle(roulette.isPeerTyping ? Color.brand : .secondary)
                }
            }
            Spacer()
            Button {
                roulette.beginReport()
            } label: {
                Image(systemName: "flag")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .background(Color.appSurface, in: Circle())
                    .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Пожаловаться")
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    Label {
                        Text("Анонимная переписка. Имя и фото откроются, если вы оба нажмёте «Нравится». Фото и ссылки здесь не отправить.")
                    } icon: {
                        Image(systemName: "lock.fill").foregroundStyle(Color.champagne)
                    }
                    .font(.app(.footnote))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.champagneSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.champagne.opacity(0.3), lineWidth: 1))
                    .padding(.bottom, 4)

                    ForEach(roulette.messages) { message in
                        RouletteBubble(message: message)
                    }
                    if let question = shownIcebreaker {
                        icebreakerCard(question)
                            .padding(.top, 8)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    Color.clear.frame(height: 1).id(Self.bottomId)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: roulette.messages.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
            }
            .onChange(of: icebreaker) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 6) {
            if let notice = roulette.notice {
                Text(notice)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            HStack(spacing: 8) {
                Button(action: roulette.stop) {
                    Label("Стоп", systemImage: "xmark")
                        .font(.app(.subheadline, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 44)
                        .background(Color.appSurface, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
                }
                Button(action: roulette.like) {
                    Label {
                        Text(roulette.liked ? likedTitle : String(localized: "Нравится"))
                    } icon: {
                        Image(systemName: roulette.liked ? "heart.fill" : "heart")
                    }
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.brandSoft, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.brand.opacity(roulette.liked ? 0.5 : 0.25), lineWidth: 1))
                }
                .disabled(roulette.liked)
                .accessibilityAddTraits(roulette.liked ? .isSelected : [])
                Button(action: roulette.next) {
                    HStack(spacing: 6) {
                        Text("Далее")
                        Image(systemName: "arrow.right")
                    }
                    .font(.app(.subheadline, weight: .bold))
                    .foregroundStyle(Color.appBackground)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(Color.champagne, in: Capsule())
                }
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .animation(.easeInOut(duration: 0.2), value: roulette.notice)
    }

    /// Пустая переписка — вопрос показывается сам, пока его не вставили или не закрыли.
    private var shownIcebreaker: String? {
        if icebreakerDismissed { return nil }
        if let icebreaker { return icebreaker }
        return roulette.messages.isEmpty ? RouletteIcebreakers.first(for: session.id) : nil
    }

    /// Макет «Переписка — случайный вопрос».
    private func icebreakerCard(_ question: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("СЛУЧАЙНЫЙ ВОПРОС", systemImage: "lightbulb")
                    .font(.app(.caption, weight: .bold))
                    .foregroundStyle(Color.champagne)
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { icebreakerDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Закрыть")
            }
            Text(question)
                .font(.app(.callout, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    draft = question
                    isInputFocused = true
                    withAnimation(.easeOut(duration: 0.2)) { icebreakerDismissed = true }
                } label: {
                    Text("Вставить в сообщение")
                        .font(.app(.subheadline, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 42)
                        .background(.brandFill, in: Capsule())
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { icebreaker = RouletteIcebreakers.random(excluding: question) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 42, height: 42)
                        .background(Color.appElevated, in: Circle())
                        .overlay(Circle().strokeBorder(Color.appLine, lineWidth: 1))
                }
                .accessibilityLabel("Другой вопрос")
            }
            .buttonStyle(PressableButtonStyle())
        }
        .padding(16)
        .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.champagne.opacity(0.32), lineWidth: 1))
    }

    private var likedTitle: String {
        session.peer.isFemale ? String(localized: "Ждём её ответа") : String(localized: "Ждём его ответа")
    }

    private var input: some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    icebreakerDismissed = false
                    icebreaker = RouletteIcebreakers.random(excluding: shownIcebreaker)
                }
            } label: {
                Image(systemName: "lightbulb")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.champagne)
                    .frame(width: 44, height: 44)
                    .background(Color.champagne.opacity(0.12), in: Circle())
                    .overlay(Circle().strokeBorder(Color.champagne.opacity(0.45), lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Случайный вопрос")
            TextField("Сообщение", text: $draft, axis: .vertical)
                .font(.app(.body))
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.appSurface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.appLine, lineWidth: 1))
                .onChange(of: draft) { _, text in
                    if !text.isEmpty { roulette.userIsTyping() }
                }
            Button {
                roulette.send(draft)
                draft = ""
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(canSend ? .white : .secondary)
                    .frame(width: 44, height: 44)
                    .background {
                        if canSend {
                            Circle().fill(.brandFill)
                        } else {
                            Circle().fill(Color.appElevated)
                        }
                    }
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!canSend)
            .accessibilityLabel("Отправить")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }
}

private struct RouletteBubble: View {
    let message: RouletteChatMessage

    var body: some View {
        HStack {
            if message.isMine { Spacer(minLength: 60) }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(message.text)
                    .font(.app(.body))
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.app(size: 11))
                    .opacity(0.75)
            }
            .foregroundStyle(message.isMine ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background {
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: 18,
                    bottomLeadingRadius: message.isMine ? 18 : 6,
                    bottomTrailingRadius: message.isMine ? 6 : 18,
                    topTrailingRadius: 18,
                    style: .continuous
                )
                if message.isMine {
                    shape.fill(.brandFill)
                } else {
                    shape.fill(Color.appSurface).overlay(shape.strokeBorder(Color.appLine, lineWidth: 1))
                }
            }
            .opacity(message.isPending ? 0.6 : 1)
            if !message.isMine { Spacer(minLength: 60) }
        }
    }
}

/// Вопросы, с которых легко начать разговор незнакомым людям, — вместо «привет, как дела».
enum RouletteIcebreakers {
    static let all: [String] = [
        String(localized: "Если бы завтра был выходной без дел — как бы вы его провели?"),
        String(localized: "Какое место в Таджикистане вы советуете увидеть каждому?"),
        String(localized: "Что вас может рассмешить даже в плохой день?"),
        String(localized: "Какое блюдо вы готовите лучше всего?"),
        String(localized: "Чем вы занимались бы, если бы деньги не были важны?"),
        String(localized: "Какую книгу или фильм вы пересматривали больше одного раза?"),
        String(localized: "Утро или вечер — когда вы настоящий вы?"),
        String(localized: "О каком путешествии вы мечтаете?"),
        String(localized: "Что для вас идеальная первая встреча?"),
        String(localized: "Чему вы научились за последний год?"),
        String(localized: "Какая песня сейчас у вас в голове?"),
        String(localized: "Что в людях вам нравится с первой минуты?"),
        String(localized: "Плов дома или в чайхане — и почему?"),
        String(localized: "Какой совет из детства вы помните до сих пор?"),
        String(localized: "Чай или кофе — и какой именно?"),
        String(localized: "Что вас вдохновляет в вашей работе или учёбе?"),
        String(localized: "Какой праздник в году вы ждёте больше всего?"),
        String(localized: "Горы или море?"),
        String(localized: "Чем вы гордитесь, но редко рассказываете?"),
        String(localized: "Какой была бы ваша суперсила?"),
    ]

    static func random(excluding current: String?) -> String {
        all.filter { $0 != current }.randomElement() ?? all[0]
    }

    /// Первый вопрос разговора — постоянный для него, чтобы не прыгал при каждой перерисовке.
    static func first(for sessionId: String) -> String {
        all[Int(UInt(bitPattern: sessionId.hashValue) % UInt(all.count))]
    }
}
