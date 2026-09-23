import SwiftUI

struct GroupInfoView: View {
    @StateObject var viewModel: GroupInfoViewModel
    let onLeft: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showAddMember = false
    @State private var memberLeaving: ChatMember?

    private var isChannel: Bool { viewModel.detail?.type == .channel }

    var body: some View {
        List {
            if let detail = viewModel.detail {
                Section {
                    header(detail)
                        .listRowBackground(Color.clear)
                }

                Section(isChannel ? "Подписчики (\(detail.participants.count))" : "Участники (\(detail.participants.count))") {
                    ForEach(detail.participants) { member in
                        HStack(spacing: 12) {
                            AvatarView(avatarUrl: member.avatarUrl, name: member.displayName, size: 40)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(member.id == viewModel.currentUserId ? "Вы" : member.displayName)
                                    .font(.app(.body, weight: .semibold))
                                Text("@\(member.username)").font(.app(.footnote)).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if member.role == .admin {
                                Text(isChannel ? "публикует" : "админ")
                                    .font(.app(.caption, weight: .semibold))
                                    .foregroundStyle(Color.champagne)
                            }
                        }
                        .swipeActions(edge: .leading) {
                            if viewModel.isCurrentUserAdmin && member.id != viewModel.currentUserId {
                                let newRole: ParticipantRole = member.role == .admin ? .member : .admin
                                let label = isChannel
                                    ? (newRole == .admin ? "Разрешить публиковать" : "Запретить публиковать")
                                    : (newRole == .admin ? "Сделать админом" : "Снять админа")
                                Button {
                                    Task { await viewModel.setRole(newRole, for: member) }
                                } label: {
                                    Label(label, systemImage: "star")
                                }
                                .tint(.champagne)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            if canRemove(member) {
                                let isMe = member.id == viewModel.currentUserId
                                Button(role: .destructive) {
                                    Task { await viewModel.removeMember(member) }
                                } label: {
                                    Label(isMe ? (isChannel ? "Отписаться" : "Покинуть") : "Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                }

                if let me = detail.participants.first(where: { $0.id == viewModel.currentUserId }) {
                    Section {
                        Button(isChannel ? "Отписаться от канала" : "Покинуть группу", role: .destructive) {
                            memberLeaving = me
                        }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle(viewModel.detail?.title ?? (isChannel ? "Канал" : "Группа"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(isPresented: $showAddMember) {
            NewChatView { user, _ in
                showAddMember = false
                Task { await viewModel.addMember(user) }
            }
        }
        .confirmationDialog(
            isChannel ? "Отписаться от канала?" : "Покинуть группу?",
            isPresented: Binding(get: { memberLeaving != nil }, set: { if !$0 { memberLeaving = nil } }),
            titleVisibility: .visible,
            presenting: memberLeaving
        ) { me in
            Button(isChannel ? "Отписаться" : "Покинуть", role: .destructive) {
                Task { await viewModel.removeMember(me) }
            }
        }
        .onChange(of: viewModel.didLeave) { _, didLeave in
            guard didLeave else { return }
            dismiss()
            onLeft()
        }
    }

    /// Обложка: буква названия, тип и число участников; добавление — здесь же, если я админ.
    private func header(_ detail: ChatDetail) -> some View {
        VStack(spacing: 8) {
            AvatarView(avatarUrl: nil, name: detail.title ?? "", size: 92)
            Text(detail.title ?? (isChannel ? "Канал" : "Группа"))
                .font(.display(.title3))
                .multilineTextAlignment(.center)
            Text("\(isChannel ? "канал" : "группа") · \(detail.participants.count) \(isChannel ? "подписчиков" : "участников")")
                .font(.app(.footnote))
                .foregroundStyle(.secondary)
            if viewModel.isCurrentUserAdmin {
                Button { showAddMember = true } label: {
                    Label(isChannel ? "Добавить подписчика" : "Добавить участника", systemImage: "person.badge.plus")
                }
                .buttonStyle(.appSecondary)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func canRemove(_ member: ChatMember) -> Bool {
        member.id == viewModel.currentUserId || viewModel.isCurrentUserAdmin
    }
}
