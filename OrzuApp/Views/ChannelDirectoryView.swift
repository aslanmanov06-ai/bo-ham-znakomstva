import SwiftUI

struct ChannelDirectoryView: View {
    @Environment(\.dismiss) private var dismiss
    let onJoin: (PublicChannel) -> Void

    @State private var query = ""
    @State private var results: [PublicChannel] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List(results) { channel in
                HStack {
                    VStack(alignment: .leading) {
                        Text(channel.title).font(.app(.headline))
                        if let username = channel.username {
                            Text("@\(username) · \(channel.subscriberCount) подписчиков")
                                .font(.app(.footnote))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button("Подписаться") { onJoin(channel) }
                        .buttonStyle(.borderedProminent)
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
            .searchable(text: $query, prompt: "Название или @username канала")
            .onChange(of: query) { _, newValue in
                searchTask?.cancel()
                searchTask = Task { await search(newValue) }
            }
            .navigationTitle("Каналы")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
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
            results = try await APIClient.shared.searchChannels(query: query)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
