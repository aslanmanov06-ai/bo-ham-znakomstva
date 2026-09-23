import SwiftUI

/// Пары и первые сообщения: кто ждёт ответа, кому написали вы и с кем уже есть пара.
struct MatchesView: View {
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var matches: MatchesViewModel

    @State private var openedIntro: IncomingIntro?

    var body: some View {
        List {
            if !newMatches.isEmpty {
                Section("Новые пары") {
                    newMatchesStrip
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            }

            if !matches.incoming.isEmpty {
                Section("Вам написали") {
                    ForEach(matches.incoming) { intro in
                        Button {
                            openedIntro = intro
                        } label: {
                            introRow(photoId: intro.from.photoIds.first, title: intro.from.displayName, text: intro.text, expiresAt: intro.expiresAt)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !matches.sent.isEmpty {
                Section("Вы написали") {
                    ForEach(matches.sent) { intro in
                        introRow(photoId: intro.to.photoId, title: intro.to.displayName, text: intro.text, expiresAt: intro.expiresAt)
                    }
                }
            }

            Section("Пары") {
                if matches.matches.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "heart.circle")
                            .font(.system(size: 40))
                            .foregroundStyle(DatingStyle.brandGradient)
                        Text("Пар пока нет. Пара возникает, когда лайк взаимный или вам ответили на первое сообщение.")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                ForEach(matches.matches) { match in
                    NavigationLink {
                        MatchDetailView(match: match, dating: dating, matches: matches)
                    } label: {
                        matchRow(match)
                    }
                }
            }
        }
        .appScreenBackground()
        .animation(DatingStyle.spring, value: matches.matches)
        .animation(DatingStyle.spring, value: matches.incoming)
        .navigationTitle("Пары")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await matches.load() }
        .task { await matches.load() }
        .sheet(item: $openedIntro) { intro in
            NavigationStack {
                IntroReplyView(intro: intro, catalog: dating.catalog, matches: matches)
            }
        }
        .alert("Ошибка", isPresented: .constant(matches.errorMessage != nil)) {
            Button("Ок") { matches.errorMessage = nil }
        } message: {
            Text(matches.errorMessage ?? "")
        }
    }

    /// Пары, где ещё никто не написал: их показываем крупно, чтобы не потерялись в списке.
    private var newMatches: [DatingMatch] {
        matches.matches.filter { !$0.hasMessages }
    }

    private var newMatchesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(newMatches) { match in
                    NavigationLink {
                        MatchDetailView(match: match, dating: dating, matches: matches)
                    } label: {
                        VStack(spacing: 6) {
                            RingedAvatar(photoId: match.partner.photoId, size: 68, highlighted: true)
                            Text(match.partner.displayName)
                                .font(.app(.caption, weight: .semibold))
                                .lineLimit(1)
                        }
                        .frame(width: 76)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func introRow(photoId: String?, title: String, text: String, expiresAt: Date) -> some View {
        HStack(spacing: 12) {
            RingedAvatar(photoId: photoId, size: 52, highlighted: false)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.app(.headline))
                Text(text)
                    .font(.app(.subheadline))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Label {
                    Text("Исчезнет через \(expiresAt, style: .relative)")
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.app(.caption2))
                .foregroundStyle(expiresSoon(expiresAt) ? AnyShapeStyle(DatingStyle.rose) : AnyShapeStyle(.tertiary))
            }
        }
        .padding(.vertical, 2)
    }

    private func expiresSoon(_ date: Date) -> Bool {
        date.timeIntervalSinceNow < Self.expiresSoonInterval
    }

    /// Меньше трёх часов до исчезновения — подсвечиваем, чтобы успели ответить.
    private static let expiresSoonInterval: TimeInterval = 3 * 60 * 60

    private func matchRow(_ match: DatingMatch) -> some View {
        HStack(spacing: 12) {
            RingedAvatar(photoId: match.partner.photoId, size: 52, highlighted: !match.hasMessages)
            VStack(alignment: .leading, spacing: 3) {
                Text("\(match.partner.displayName), \(match.partner.age)")
                    .font(.app(.headline))
                Text(match.hasMessages ? "Переписка началась" : "Напишите первым")
                    .font(.app(.footnote))
                    .foregroundStyle(match.hasMessages ? AnyShapeStyle(.secondary) : AnyShapeStyle(DatingStyle.rose))
            }
        }
        .padding(.vertical, 2)
    }
}

/// Круглое фото; у новых пар — фирменное кольцо, как у непросмотренных историй.
struct RingedAvatar: View {
    let photoId: String?
    let size: CGFloat
    let highlighted: Bool

    var body: some View {
        DatingPhotoView(attachmentId: photoId, cornerRadius: size / 2)
            .frame(width: size, height: size)
            .padding(highlighted ? 3 : 0)
            .background {
                if highlighted {
                    Circle().fill(Color.appBackground)
                }
            }
            .padding(highlighted ? 2.5 : 0)
            .background {
                if highlighted {
                    Circle().fill(DatingStyle.brandGradient)
                }
            }
    }
}

/// Ответ на первое сообщение: ответ создаёт пару, отказ убирает сообщение (отправителю об этом не сообщают).
struct IntroReplyView: View {
    let intro: IncomingIntro
    let catalog: DatingCatalog?
    @ObservedObject var matches: MatchesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var isSending = false
    @State private var showProfile = false

    var body: some View {
        Form {
            Section {
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 12) {
                        DatingPhotoView(attachmentId: intro.from.photoIds.first, cornerRadius: 10)
                            .frame(width: 56, height: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(intro.from.displayName), \(intro.from.age)")
                                    .font(.app(.headline))
                                if intro.from.verified {
                                    VerifiedBadge()
                                }
                            }
                            Text("Открыть анкету")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Сообщение") {
                Text(intro.text)
            }

            Section("Ваш ответ") {
                TextField("Ответьте, чтобы начать общение", text: $text, axis: .vertical)
                    .lineLimit(3...6)
                Button("Ответить") { reply() }
                    .disabled(isSending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section {
                Button("Отклонить", role: .destructive) { decline() }
                    .disabled(isSending)
            } footer: {
                Text("Отправитель не узнает об отказе — сообщение просто исчезнет.")
            }
        }
        .appScreenBackground()
        .navigationTitle("Первое сообщение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                DatingProfileDetailView(profile: intro.from, catalog: catalog)
            }
        }
    }

    private func reply() {
        isSending = true
        Task {
            defer { isSending = false }
            let match = await matches.reply(to: intro, text: text.trimmingCharacters(in: .whitespacesAndNewlines))
            if let chatId = match?.chatId {
                // Переписка продолжается в чате пары — открываем его на вкладке «Чаты».
                PushManager.shared.pendingChatId = chatId
            }
            if match != nil {
                dismiss()
            }
        }
    }

    private func decline() {
        isSending = true
        Task {
            defer { isSending = false }
            await matches.decline(intro)
            dismiss()
        }
    }
}
