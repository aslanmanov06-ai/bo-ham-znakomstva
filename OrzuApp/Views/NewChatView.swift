import SwiftUI

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    /// Второй аргумент — открыть секретный (сквозь-шифрованный) чат вместо обычного.
    let onSelect: (User, Bool) -> Void

    @State private var query = ""
    @State private var results: [User] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var isSecret = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $isSecret) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.champagne)
                                .frame(width: 38, height: 38)
                                .background(Color.champagne.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Секретный чат").font(.app(.body, weight: .semibold))
                                Text("Текст видят только ваши два устройства. Без вложений, с ботами недоступен.")
                                    .font(.app(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // С ботом секретный чат невозможен — сервер всё равно откажет, поэтому просто не показываем их.
                let found = results.filter { !isSecret || $0.isBot != true }
                if !found.isEmpty {
                    Section {
                        ForEach(found) { user in
                            Button {
                                onSelect(user, isSecret)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(avatarUrl: user.avatarUrl, name: user.displayName, size: 46)
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(user.displayName).font(.app(.body, weight: .semibold))
                                            if user.isBot == true { BotBadge() }
                                        }
                                        Text("@\(user.username)").font(.app(.subheadline)).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text("Найдено")
                    } footer: {
                        Text("С кем ещё нет переписки, первое сообщение уйдёт запросом — чат откроется, когда ответят.")
                    }
                }
            }
            .appScreenBackground()
            .overlay {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if results.isEmpty && !query.isEmpty {
                    ContentUnavailableView.search
                }
            }
            .searchable(text: $query, prompt: "Найти по username или имени")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task { await search(newValue) }
            }
            .navigationTitle("Новый чат")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
            }
        }
    }

    private func search(_ query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        try? await Task.sleep(nanoseconds: 300_000_000)
        guard !Task.isCancelled else { return }

        do {
            results = try await APIClient.shared.searchUsers(query: query)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
