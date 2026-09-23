import SwiftUI

/// Пара: «Путь к браку», вопросы для разговора, чек-лист безопасности и встречи.
struct MatchDetailView: View {
    let match: DatingMatch
    @ObservedObject var dating: DatingViewModel
    @ObservedObject var matches: MatchesViewModel

    @StateObject private var model: MatchDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showProfile = false
    @State private var meetingToEdit: MeetingEditing?
    @State private var confirmUnmatch = false
    @State private var sentQuestion: String?

    init(match: DatingMatch, dating: DatingViewModel, matches: MatchesViewModel) {
        self.match = match
        self.dating = dating
        self.matches = matches
        _model = StateObject(wrappedValue: MatchDetailViewModel(matchId: match.id))
    }

    var body: some View {
        List {
            partnerSection
            journeySection
            questionsSection
            checklistSection
            meetingsSection
            Section {
                Button("Удалить пару", role: .destructive) { confirmUnmatch = true }
            } footer: {
                Text("Чат пары удалится у обоих, и эта пара больше не возникнет.")
            }
        }
        .appScreenBackground()
        .navigationTitle(match.partner.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $showProfile) {
            NavigationStack {
                PartnerProfileView(userId: match.partner.userId, catalog: dating.catalog)
            }
        }
        .sheet(item: $meetingToEdit) { editing in
            NavigationStack {
                MeetingComposerView(editing: editing, partnerName: match.partner.displayName, partnerPhotoId: match.partner.photoId) { startsAt, place, note in
                    switch editing.mode {
                    case .propose:
                        await model.proposeMeeting(startsAt: startsAt, place: place, note: note)
                    case .reschedule(let meeting):
                        await model.reschedule(meeting, startsAt: startsAt, place: place, note: note)
                    }
                }
            }
        }
        .confirmationDialog("Удалить пару?", isPresented: $confirmUnmatch, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) {
                Task {
                    await matches.unmatch(match)
                    dismiss()
                }
            }
            Button("Отмена", role: .cancel) {}
        }
        .alert("Ошибка", isPresented: .constant(model.errorMessage != nil)) {
            Button("Ок") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert("Отправлено", isPresented: .constant(model.sharedWithCount != nil)) {
            Button("Ок") { model.sharedWithCount = nil }
        } message: {
            Text("Доверенных контактов получили место и время встречи: \(model.sharedWithCount ?? 0)")
        }
        .alert("Вопрос отправлен в чат", isPresented: .constant(sentQuestion != nil)) {
            Button("Ок") { sentQuestion = nil }
        } message: {
            Text(sentQuestion ?? "")
        }
    }

    // MARK: - Разделы

    private var partnerSection: some View {
        Section {
            VStack(spacing: 12) {
                RingedAvatar(photoId: match.partner.photoId, size: 96, highlighted: true)
                VStack(spacing: 4) {
                    Text("\(match.partner.displayName), \(match.partner.age)")
                        .font(.display(.title3))
                    Text("Пара с \(match.createdAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.app(.caption))
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button { showProfile = true } label: {
                        Label("Анкета", systemImage: "person.text.rectangle")
                    }
                    .buttonStyle(.appSecondary)
                    if let chatId = match.chatId {
                        Button { PushManager.shared.pendingChatId = chatId } label: {
                            Label("Чат", systemImage: "bubble.left.and.bubble.right.fill")
                        }
                        .buttonStyle(.appPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var journeySection: some View {
        if let journey = model.journey, let stage = dating.catalog?.stage(journey.stage) {
            Section {
                JourneyProgress(stages: dating.catalog?.journey.stages ?? [], current: journey.stage)
                    .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.name)
                        .font(.display(.headline))
                    Text(stage.description)
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
                if journey.endedAt != nil {
                    Text("Путь завершён")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                } else if let proposal = journey.proposal {
                    proposalRow(proposal)
                } else if let next = nextStage(after: journey.stage) {
                    Button("Предложить: \(next.name)", systemImage: "arrow.right.circle") {
                        Task { await model.proposeStage(next.code) }
                    }
                    .disabled(model.isBusy)
                }
            } header: {
                Text("Путь к браку")
            } footer: {
                Text("Ступень меняется, только когда её подтвердили оба. Со ступени «Мы нашли друг друга» анкеты обоих скрываются из ленты.")
            }
        }
    }

    @ViewBuilder
    private func proposalRow(_ proposal: StageProposal) -> some View {
        let name = dating.catalog?.stage(proposal.stage)?.name ?? proposal.stage
        if proposal.byMe {
            VStack(alignment: .leading, spacing: 8) {
                Text("Вы предложили: \(name). Ждём ответа.")
                    .font(.app(.subheadline))
                Button("Отменить предложение", role: .destructive) {
                    Task { await model.dropProposal() }
                }
                .disabled(model.isBusy)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(match.partner.displayName) предлагает: \(name)")
                    .font(.app(.subheadline))
                HStack(spacing: 12) {
                    Button("Согласиться") {
                        Task { await model.proposeStage(proposal.stage) }
                    }
                    .glassProminentButtonStyle()
                    Button("Пока нет", role: .destructive) {
                        Task { await model.dropProposal() }
                    }
                    .glassButtonStyle()
                }
                .disabled(model.isBusy)
            }
        }
    }

    @ViewBuilder
    private var questionsSection: some View {
        if let journey = model.journey,
           let stage = dating.catalog?.stage(journey.stage),
           !stage.questions.isEmpty,
           let chatId = match.chatId {
            Section {
                ForEach(stage.questions, id: \.self) { question in
                    Button {
                        send(question: question, chatId: chatId)
                    } label: {
                        HStack(spacing: 10) {
                            Text(question)
                                .font(.app(.subheadline))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.champagne)
                        }
                        .padding(12)
                        .background(Color.appElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } header: {
                Text("О чём поговорить")
            } footer: {
                Text("Нажмите на вопрос — он уйдёт в чат пары.")
            }
        }
    }

    @ViewBuilder
    private var checklistSection: some View {
        if let journey = model.journey, let items = dating.catalog?.journey.checklist, !items.isEmpty {
            Section {
                ForEach(items) { item in
                    Button {
                        Task { await model.toggleChecklist(item.code) }
                    } label: {
                        HStack {
                            Image(systemName: journey.checklist.mine.contains(item.code) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.tint)
                            Text(item.name)
                                .font(.app(.subheadline))
                                .foregroundStyle(.primary)
                            Spacer()
                            if journey.checklist.partner.contains(item.code) {
                                Image(systemName: "person.fill.checkmark")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(model.isBusy)
                }
            } header: {
                Text("Перед первой встречей")
            } footer: {
                Text("Свои пункты отмечаете вы, отметки собеседника видны значком рядом.")
            }
        }
    }

    private var meetingsSection: some View {
        Section {
            if let meeting = model.activeMeeting {
                meetingRow(meeting, active: true)
            }
            Button("Предложить встречу", systemImage: "calendar.badge.plus") {
                meetingToEdit = MeetingEditing(mode: .propose)
            }
            .disabled(model.isBusy)

            ForEach(pastMeetings) { meeting in
                meetingRow(meeting, active: false)
            }
        } header: {
            Text("Встречи")
        } footer: {
            Text("Назначенной встречей можно поделиться с доверенными контактами — им придут место и время.")
        }
    }

    private var pastMeetings: [DatingMeeting] {
        let activeId = model.activeMeeting?.id
        return model.meetings.filter { $0.id != activeId }
    }

    @ViewBuilder
    private func meetingRow(_ meeting: DatingMeeting, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.startsAt.formatted(date: .abbreviated, time: .shortened))
                .font(.app(.subheadline, weight: .semibold))
            Text(meeting.place)
                .font(.app(.subheadline))
            if !meeting.note.isEmpty {
                Text(meeting.note)
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
            }
            Text(statusText(meeting))
                .font(.app(.caption))
                .foregroundStyle(.secondary)

            if active {
                meetingActions(meeting)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func meetingActions(_ meeting: DatingMeeting) -> some View {
        if meeting.status == .proposed, !meeting.byMe, !meeting.expired {
            HStack(spacing: 12) {
                Button("Принять") { Task { await model.accept(meeting) } }
                    .glassProminentButtonStyle()
                Button("Отклонить") { Task { await model.decline(meeting) } }
                    .glassButtonStyle()
                Button("Другое время") { meetingToEdit = MeetingEditing(mode: .reschedule(meeting)) }
                    .glassButtonStyle()
            }
            .disabled(model.isBusy)
        } else if meeting.status == .accepted {
            HStack(spacing: 12) {
                Button("Поделиться с близкими") { Task { await model.share(meeting) } }
                    .glassButtonStyle()
                Button("Отменить", role: .destructive) { Task { await model.cancel(meeting) } }
                    .glassButtonStyle()
            }
            .disabled(model.isBusy)
        } else if meeting.status == .proposed, meeting.byMe {
            Button("Отменить приглашение", role: .destructive) { Task { await model.cancel(meeting) } }
                .glassButtonStyle()
                .disabled(model.isBusy)
        }
    }

    private func statusText(_ meeting: DatingMeeting) -> String {
        switch meeting.status {
        case .proposed:
            if meeting.expired { return "Не состоялось — никто не ответил вовремя" }
            return meeting.byMe ? "Вы пригласили, ждём ответа" : "Вас пригласили"
        case .accepted:
            return "Встреча назначена"
        case .declined:
            return "Отклонено"
        case .cancelled:
            return meeting.cancelledByMe == true ? "Вы отменили" : "Отменено собеседником"
        case .rescheduled:
            return "Предложено другое время"
        }
    }

    private func nextStage(after code: String) -> JourneyStageInfo? {
        guard
            let stages = dating.catalog?.journey.stages,
            let index = stages.firstIndex(where: { $0.code == code }),
            index + 1 < stages.count
        else { return nil }
        return stages[index + 1]
    }

    /// Через очередь: без сети вопрос уйдёт в чат пары, когда связь появится.
    private func send(question: String, chatId: String) {
        MessageOutbox.shared.enqueue(OutgoingMessage(id: UUID().uuidString, chatId: chatId, createdAt: Date(), text: question))
        sentQuestion = question
    }
}

/// Что именно правит экран встречи: новое приглашение или перенос полученного.
struct MeetingEditing: Identifiable {
    enum Mode {
        case propose
        case reschedule(DatingMeeting)
    }

    let mode: Mode
    let id = UUID()
}

/// Анкета собеседника по паре: она видна даже когда скрыта от остальных.
struct PartnerProfileView: View {
    let userId: String
    let catalog: DatingCatalog?

    @State private var profile: DatingProfilePublic?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let profile {
                DatingProfileDetailView(profile: profile, catalog: catalog)
            } else if let errorMessage {
                ContentUnavailableView("Анкета недоступна", systemImage: "person.slash", description: Text(errorMessage))
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                profile = try await APIClient.shared.fetchDatingProfile(userId: userId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// «Путь к браку» полосой ступеней: пройденные — гранатовые, текущая — с золотым ободком.
private struct JourneyProgress: View {
    let stages: [JourneyStageInfo]
    let current: String

    var body: some View {
        let currentIndex = stages.firstIndex { $0.code == current } ?? 0
        HStack(spacing: 4) {
            ForEach(Array(stages.enumerated()), id: \.element.code) { index, _ in
                Capsule()
                    .fill(index <= currentIndex ? AnyShapeStyle(.brandFill) : AnyShapeStyle(Color.appElevated))
                    .frame(height: 6)
                    .overlay {
                        if index == currentIndex {
                            Capsule().strokeBorder(Color.champagne, lineWidth: 1.5)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Ступень \(currentIndex + 1) из \(stages.count)")
    }
}
