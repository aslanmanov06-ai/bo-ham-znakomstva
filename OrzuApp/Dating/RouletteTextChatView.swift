import SwiftUI

/// Переписка в рулетке (макет «Переписка»): анонимный собеседник, только текст, внизу «Стоп», «Нравится», «Далее».
struct RouletteTextChatView: View {
    @ObservedObject var roulette: RouletteViewModel
    let session: RouletteViewModel.Session
    let places: RoulettePlaces

    @State private var draft = ""
    @State private var showReport = false
    @FocusState private var isInputFocused: Bool

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
        .sheet(isPresented: $showReport) {
            RouletteReportSheet(roulette: roulette, peer: session.peer)
        }
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
                showReport = true
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

    private var likedTitle: String {
        session.peer.isFemale ? String(localized: "Ждём её ответа") : String(localized: "Ждём его ответа")
    }

    private var input: some View {
        let canSend = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
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
