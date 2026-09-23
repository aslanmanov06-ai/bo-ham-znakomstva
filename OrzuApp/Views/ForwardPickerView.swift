import SwiftUI

/// Выбор чата, куда переслать сообщение. Секретные чаты и каналы, где писать нельзя, не показываем —
/// сервер туда всё равно не перешлёт.
struct ForwardPickerView: View {
    /// true — переслано, экран можно закрыть; false — ошибку уже показал вызывающий экран.
    let onPick: (Chat) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var chats: [Chat] = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(filteredChats) { chat in
                Button {
                    forward(to: chat)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(avatarUrl: chat.peer?.avatarUrl, name: chat.displayTitle, size: 40)
                        Text(chat.displayTitle).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSending)
            }
            .listStyle(.plain)
            .appScreenBackground()
            .searchable(text: $query, prompt: "Кому переслать")
            .overlay {
                if isLoading {
                    ProgressView()
                } else if let errorMessage {
                    ContentUnavailableView("Не удалось загрузить чаты", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
                } else if filteredChats.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Переслать")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private var filteredChats: [Chat] {
        let available = chats.filter { $0.canPost && $0.type != .secret }
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return available }
        return available.filter { $0.displayTitle.localizedCaseInsensitiveContains(needle) }
    }

    private func load() async {
        defer { isLoading = false }
        do {
            chats = try await APIClient.shared.fetchChats()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func forward(to chat: Chat) {
        isSending = true
        Task {
            defer { isSending = false }
            if await onPick(chat) { dismiss() }
        }
    }
}
