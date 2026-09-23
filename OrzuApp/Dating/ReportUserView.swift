import SwiftUI

/// Жалоба на пользователя: категория и необязательный комментарий. Жалобы разбирают модераторы.
struct ReportUserView: View {
    let userId: String
    let displayName: String
    /// Жалоба из чата — на конкретное сообщение.
    var messageId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var category = ReportCategory.fake
    @State private var comment = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Label {
                    Text("Модератор проверит жалобу. \(displayName) не узнает, кто пожаловался.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "flag.fill")
                        .foregroundStyle(.red)
                }
                .listRowBackground(Color.clear)
            }
            Section("Причина") {
                Picker("Причина", selection: $category) {
                    ForEach(ReportCategory.allCases) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Что произошло") {
                TextField("Необязательно", text: $comment, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .appScreenBackground()
        .navigationTitle("Пожаловаться")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Отправить", action: send)
                    .disabled(isSending)
            }
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func send() {
        isSending = true
        Task {
            defer { isSending = false }
            do {
                let text = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                try await APIClient.shared.reportUser(
                    userId: userId,
                    category: category,
                    comment: text.isEmpty ? nil : text,
                    messageId: messageId
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
