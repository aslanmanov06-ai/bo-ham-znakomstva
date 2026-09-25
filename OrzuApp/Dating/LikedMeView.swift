import SwiftUI

/// Золотая полоса над карточкой в ленте (макет «Знакомства — вход в „Вас лайкнули“»). Без лайков её нет.
struct LikedMeBanner: View {
    let cards: [DatingLikedCard]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                HStack(spacing: -9) {
                    ForEach(cards.prefix(3)) { liked in
                        DatingPhotoView(attachmentId: liked.card.profile.photoIds.first, cornerRadius: 13)
                            .frame(width: 26, height: 26)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(Color.champagneSoft, lineWidth: 2))
                    }
                }
                (Text("Вас лайкнули ") + Text(Self.peopleCount(cards.count)).foregroundStyle(Color.champagne))
                    .font(.app(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.champagne)
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(Color.champagneSoft, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.champagne.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Вас лайкнули \(Self.peopleCount(cards.count))")
    }

    /// «1 человек», «3 человека», «5 человек», «12 человек».
    static func peopleCount(_ count: Int) -> String {
        let lastTwo = count % 100
        let last = count % 10
        let word = (2...4).contains(last) && !(12...14).contains(lastTwo) ? "человека" : "человек"
        return "\(count) \(word)"
    }
}

/// «Вас лайкнули» (макет «Вас лайкнули»): кто лайкнул меня, а я ещё не ответил. Ответный лайк — пара.
struct LikedMeView: View {
    @ObservedObject var likes: LikedMeViewModel
    @ObservedObject var dating: DatingViewModel

    @State private var detail: DatingLikedCard?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Вас лайкнули")
                        .font(.display(size: 24))
                    Text("Ответьте лайком — и вы пара. Если пропустите, человек об этом не узнает.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 4)

                if likes.cards.isEmpty && !likes.isLoading {
                    ContentUnavailableView("Пока никого", systemImage: "heart", description: Text("Когда вас лайкнут в ленте, человек появится здесь."))
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(likes.cards) { liked in
                            cell(liked)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .background(AppBackground())
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await likes.load() }
        .task { await likes.load() }
        .sheet(item: $detail) { liked in
            NavigationStack {
                DatingProfileDetailView(
                    profile: liked.card.profile,
                    catalog: dating.catalog,
                    compatibility: liked.card.compatibility,
                    onLike: { Task { await likes.respond(liked, action: .like) } },
                    onSkip: { Task { await likes.respond(liked, action: .skip) } },
                    onIntro: { PushManager.shared.openConversation(with: liked.card.profile) }
                )
            }
        }
        .fullScreenCover(item: $likes.newMatch) { match in
            MatchCelebrationView(match: match, myPhotoId: dating.profile?.shared.photoIds.first) {
                likes.newMatch = nil
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { likes.errorMessage != nil }, set: { if !$0 { likes.errorMessage = nil } })) {
            Button("Ок") { likes.errorMessage = nil }
        } message: {
            Text(likes.errorMessage ?? "")
        }
    }

    private func cell(_ liked: DatingLikedCard) -> some View {
        let profile = liked.card.profile
        return VStack(spacing: 8) {
            Button { detail = liked } label: {
                DatingPhotoView(attachmentId: profile.photoIds.first, cornerRadius: 0)
                    .frame(height: 232)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .topLeading) {
                        Text("\(liked.card.compatibility.score)%")
                            .font(.app(size: 11.5, weight: .bold))
                            .foregroundStyle(Color.appBackground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.champagne, in: Capsule())
                            .padding(8)
                    }
                    .overlay(alignment: .topTrailing) {
                        Text(Self.whenLabel(liked.likedAt))
                            .font(.app(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.45), in: Capsule())
                            .padding(8)
                    }
                    .overlay(alignment: .bottomLeading) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Text("\(profile.displayName), \(profile.age)")
                                    .font(.app(size: 15, weight: .bold))
                                    .lineLimit(1)
                                if profile.verified {
                                    VerifiedBadge()
                                        .font(.app(size: 14))
                                }
                            }
                            Text(profile.locationLine(catalog: dating.catalog))
                                .font(.app(size: 12))
                                .opacity(0.9)
                                .lineLimit(1)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.top, 40)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(profile.displayName), \(profile.age), совместимость \(liked.card.compatibility.score)%")

            HStack(spacing: 8) {
                Button { Task { await likes.respond(liked, action: .skip) } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.appElevated, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.appLine, lineWidth: 1))
                }
                .accessibilityLabel("Пропустить")
                Button { Task { await likes.respond(liked, action: .like) } } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Color.brand, in: Capsule())
                }
                .accessibilityLabel("Нравится")
            }
            .buttonStyle(.plain)
        }
    }

    /// «сегодня», «вчера», «23 сент.» — когда поставлен лайк.
    private static func whenLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "сегодня" }
        if calendar.isDateInYesterday(date) { return "вчера" }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
