import SwiftUI

struct NewChannelView: View {
    @Environment(\.dismiss) private var dismiss
    let onCreate: (String, String) -> Void

    @State private var title = ""
    @State private var username = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Название") {
                    TextField("Например, Новости", text: $title)
                }
                Section {
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Публичная ссылка")
                } footer: {
                    Text("Только латиница, цифры и подчёркивание, 3–32 символа. По нему канал ищут и на него подписываются.")
                }
            }
            .appScreenBackground()
            .navigationTitle("Новый канал")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        onCreate(title.trimmingCharacters(in: .whitespaces), username.trimmingCharacters(in: .whitespaces))
                    }
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty, (3...32).contains(trimmedUsername.count) else { return false }
        return trimmedUsername.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
    }
}
