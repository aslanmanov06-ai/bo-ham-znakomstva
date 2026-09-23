import SwiftUI

/// Анкета целиком: фото, видео, совместимость и всё, что человек о себе указал.
/// Используется и для кандидата из ленты, и для собеседника из пары, и для предпросмотра своей анкеты.
struct DatingProfileDetailView: View {
    let profile: DatingProfilePublic
    let catalog: DatingCatalog?
    var compatibility: Compatibility?
    /// Предпросмотр своей анкеты: жаловаться на себя и блокировать себя незачем.
    var showsModeration = true
    var onLike: (() -> Void)?
    var onSkip: (() -> Void)?
    var onIntro: (() -> Void)?
    /// «Написать»: открыть личный чат или, если его нет, запрос на переписку. Экран сам не закрывается —
    /// чат или запрос открывает тот, кто показал анкету.
    var onMessage: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var showReport = false
    @State private var blockError: String?
    @State private var confirmBlock = false
    @State private var photoIndex = 0

    private let heroHeight: CGFloat = 520

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                hero
                if let compatibility {
                    compatibilityCard(compatibility)
                }
                if !profile.bio.isEmpty {
                    card("О себе", systemImage: "quote.opening") {
                        Text(profile.bio)
                            .font(.app(.body))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let videoId = profile.videoId {
                    card("Видео", systemImage: "play.rectangle") {
                        DatingVideoView(attachmentId: videoId)
                            .frame(height: 260)
                    }
                }
                factsCard
                chips("Интересы", systemImage: "star", codes: profile.interests, items: catalog?.interests ?? [])
                chips("Занятия", systemImage: "figure.walk", codes: profile.hobbies, items: catalog?.hobbies ?? [])
                chips("Любимая кухня", systemImage: "fork.knife", codes: profile.cuisines, items: catalog?.cuisines ?? [])
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
        .background(DatingBackdrop())
        .safeAreaInset(edge: .bottom) { actions }
        .navigationTitle(profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if showsModeration {
                    Menu {
                        Button("Пожаловаться", systemImage: "flag") { showReport = true }
                        Button("Заблокировать", systemImage: "hand.raised", role: .destructive) { confirmBlock = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("Ещё")
                }
            }
        }
        .sheet(isPresented: $showReport) {
            NavigationStack {
                ReportUserView(userId: profile.userId, displayName: profile.displayName)
            }
        }
        .confirmationDialog("Заблокировать \(profile.displayName)?", isPresented: $confirmBlock, titleVisibility: .visible) {
            Button("Заблокировать", role: .destructive) { block() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Вы перестанете видеть анкету и сообщения этого человека, а он — вашу.")
        }
        .alert("Ошибка", isPresented: .constant(blockError != nil)) {
            Button("Ок") { blockError = nil }
        } message: {
            Text(blockError ?? "")
        }
    }

    /// Фото на всю ширину: листаются свайпом, сверху — полоски-индикаторы, снизу — имя поверх затемнения.
    private var hero: some View {
        TabView(selection: $photoIndex) {
            ForEach(Array(profile.photoIds.enumerated()), id: \.element) { index, photoId in
                DatingPhotoView(attachmentId: photoId, cornerRadius: 0)
                    .tag(index)
            }
            if profile.photoIds.isEmpty {
                DatingPhotoView(attachmentId: nil, cornerRadius: 0)
                    .tag(0)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(height: heroHeight)
        .overlay(alignment: .top) { photoPager }
        .overlay(alignment: .bottom) { heroCaption }
        .clipShape(RoundedRectangle(cornerRadius: DatingStyle.cardCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 8)
        .sensoryFeedback(.selection, trigger: photoIndex)
    }

    @ViewBuilder
    private var photoPager: some View {
        if profile.photoIds.count > 1 {
            HStack(spacing: 4) {
                ForEach(profile.photoIds.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == photoIndex ? Color.white : Color.white.opacity(0.35))
                        .frame(height: 3.5)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .shadow(color: .black.opacity(0.25), radius: 2)
            .animation(.easeOut(duration: 0.2), value: photoIndex)
        }
    }

    private var heroCaption: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(profile.displayName)
                    .font(.display(size: 28, weight: .semibold))
                Text("\(profile.age)")
                    .font(.display(size: 24, weight: .medium))
                if profile.verified {
                    VerifiedBadge()
                        .font(.app(.title3))
                }
            }
            Label(location, systemImage: "mappin.and.ellipse")
                .font(.app(.subheadline, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            if let username = profile.username {
                Text("@\(username)")
                    .font(.app(.subheadline))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .padding(.top, 60)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        }
        .allowsHitTesting(false)
    }

    private func compatibilityCard(_ compatibility: Compatibility) -> some View {
        card("Совместимость", systemImage: "sparkles") {
            HStack(alignment: .top, spacing: 16) {
                CompatibilityRing(score: compatibility.score, size: 72, lineWidth: 7, trackColor: DatingStyle.rose.opacity(0.15))
                    .foregroundStyle(.primary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(compatibility.reasons, id: \.self) { reason in
                        Label {
                            Text(reason)
                                .font(.app(.subheadline))
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DatingStyle.rose)
                        }
                    }
                }
            }
        }
    }

    /// Факты плитками в две колонки: пробегаются глазами быстрее, чем таблица «название — значение».
    @ViewBuilder
    private var factsCard: some View {
        let facts = self.facts
        if !facts.isEmpty {
            card("Главное", systemImage: "person.text.rectangle") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(facts, id: \.title) { fact in
                        FactTile(fact: fact)
                    }
                }
            }
        }
    }

    private var facts: [ProfileFact] {
        let candidates: [ProfileFact?] = [
            fact("Цель", "heart.circle", catalog?.relationshipGoals.name(of: profile.relationshipGoal)),
            fact("Семейное положение", "person.2", catalog?.maritalStatuses.name(of: profile.maritalStatus)),
            fact("Дети", "figure.and.child.holdinghands", catalog?.children.name(of: profile.children)),
            fact("Хочет детей", "house", catalog?.wantsChildren.name(of: profile.wantsChildren)),
            fact("Образование", "graduationcap", catalog?.education.name(of: profile.education)),
            fact("Профессия", "briefcase", profile.profession),
            fact("Рост", "ruler", profile.heightCm.map { "\($0) см" }),
            fact("Курение", "smoke", catalog?.habitFrequencies.name(of: profile.smoking)),
            fact("Алкоголь", "wineglass", catalog?.habitFrequencies.name(of: profile.alcohol)),
            fact("Спорт", "figure.run", catalog?.habitFrequencies.name(of: profile.sport)),
        ]
        return candidates.compactMap { $0 }
    }

    private func fact(_ title: String, _ systemImage: String, _ value: String?) -> ProfileFact? {
        guard let value, !value.isEmpty else { return nil }
        return ProfileFact(title: title, systemImage: systemImage, value: value)
    }

    @ViewBuilder
    private func chips(_ title: String, systemImage: String, codes: [String], items: [CatalogItem]) -> some View {
        let names = items.filter { codes.contains($0.code) }.map(\.name)
        if !names.isEmpty {
            card(title, systemImage: systemImage) {
                FlowLayout(spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        DatingChip(text: name)
                    }
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        DatingSectionCard(title: title, systemImage: systemImage, content: content)
    }

    @ViewBuilder
    private var actions: some View {
        if let onMessage {
            Button(action: onMessage) {
                Label("Написать", systemImage: "bubble.left.fill")
                    .font(.app(.headline))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DatingStyle.brandGradient, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        } else if onLike != nil || onIntro != nil || onSkip != nil {
            HStack(spacing: 22) {
                if let onSkip {
                    DatingActionButton(kind: .skip, size: 58) {
                        onSkip()
                        dismiss()
                    }
                }
                if let onIntro {
                    DatingActionButton(kind: .intro, size: 48) {
                        onIntro()
                        dismiss()
                    }
                }
                if let onLike {
                    DatingActionButton(kind: .like, size: 66) {
                        onLike()
                        dismiss()
                    }
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
        }
    }

    private var location: String {
        var parts = [catalog?.cityName(countryCode: profile.countryCode, cityCode: profile.cityCode) ?? profile.cityCode]
        if let distance = profile.distanceText {
            parts.append("\(distance) от вас")
        }
        return parts.joined(separator: " · ")
    }

    private func block() {
        Task {
            do {
                try await APIClient.shared.blockUser(id: profile.userId)
                dismiss()
            } catch {
                blockError = error.localizedDescription
            }
        }
    }
}

/// Одна строка анкеты: «Рост — 180 см».
private struct ProfileFact {
    let title: String
    let systemImage: String
    let value: String
}

private struct FactTile: View {
    let fact: ProfileFact

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: fact.systemImage)
                .font(.app(.body, weight: .semibold))
                .foregroundStyle(DatingStyle.rose)
                .frame(width: 34, height: 34)
                .background(DatingStyle.rose.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.title)
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
                Text(fact.value)
                    .font(.app(.subheadline, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Теги в несколько строк: SwiftUI до iOS 16 такого контейнера не имел, а Grid здесь не подходит —
/// ширина элементов разная.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: maxWidth == .infinity ? rowWidth : maxWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
