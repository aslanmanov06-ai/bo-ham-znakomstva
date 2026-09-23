import Foundation

@MainActor
final class GroupInfoViewModel: ObservableObject {
    @Published var detail: ChatDetail?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var didLeave = false

    let chatId: String
    let currentUserId: String

    var isCurrentUserAdmin: Bool {
        detail?.participants.first(where: { $0.id == currentUserId })?.role == .admin
    }

    init(chatId: String, currentUserId: String) {
        self.chatId = chatId
        self.currentUserId = currentUserId
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            detail = try await APIClient.shared.fetchChatDetail(chatId: chatId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addMember(_ user: User) async {
        do {
            try await APIClient.shared.addMember(chatId: chatId, userId: user.id)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setRole(_ role: ParticipantRole, for member: ChatMember) async {
        do {
            try await APIClient.shared.updateMemberRole(chatId: chatId, userId: member.id, role: role)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeMember(_ member: ChatMember) async {
        do {
            try await APIClient.shared.removeMember(chatId: chatId, userId: member.id)
            if member.id == currentUserId {
                // Группа для нас больше недоступна (403 на повторный fetch) — экран должен закрыться, а не показывать ошибку.
                didLeave = true
            } else {
                await load()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
