import SwiftUI

/// Поиск по тексту сообщений чата на сервере. Выбранное сообщение показывает ChatView.
struct MessageSearchView: View {
    @ObservedObject var viewModel: ChatViewModel
    let onSelect: (Message) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Message] = []
    @State private var searchedQuery: String?

    var body: some View {
        NavigationStack {
            List(results) { message in
                Button {
                    onSelect(message)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(viewModel.displayName(of: message.senderId)).font(.app(.subheadline, weight: .bold))
                            Spacer()
                            Text(message.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Text(message.previewText).font(.app(.subheadline)).lineLimit(3)
                    }
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .appScreenBackground()
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Поиск сообщений")
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).count < ChatViewModel.minSearchLength {
                    ContentUnavailableView("Поиск по чату", systemImage: "magnifyingglass", description: Text("Введите хотя бы \(ChatViewModel.minSearchLength) символа"))
                } else if let searchedQuery, results.isEmpty {
                    ContentUnavailableView.search(text: searchedQuery)
                }
            }
            // Запрос уходит после паузы в наборе, а не на каждую букву; новый ввод отменяет прежний поиск.
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                let found = await viewModel.search(query)
                guard !Task.isCancelled else { return }
                results = found
                searchedQuery = query
            }
            .navigationTitle("Поиск")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}
