import SwiftUI
import UIKit

/// Управление своими ботами (аналог @BotFather): создание, перевыпуск токена, удаление.
struct BotsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BotsViewModel()
    @State private var username = ""
    @State private var displayName = ""
    @State private var botToDelete: Bot?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("username, оканчивается на bot", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Имя", text: $displayName)
                    Button("Создать бота") {
                        Task {
                            if await viewModel.create(username: username, displayName: displayName) {
                                username = ""
                                displayName = ""
                            }
                        }
                    }
                    .disabled(username.count < 3 || displayName.isEmpty)
                } header: {
                    Text("Новый бот")
                } footer: {
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }

                Section("Мои боты") {
                    ForEach(viewModel.bots) { bot in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bot.displayName).font(.app(.headline))
                            Text("@\(bot.username)").font(.app(.subheadline)).foregroundStyle(.secondary)
                            if let webhookUrl = bot.webhookUrl {
                                Text("webhook: \(webhookUrl)").font(.app(.caption)).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .swipeActions {
                            Button("Удалить", role: .destructive) { botToDelete = bot }
                            Button("Новый токен") { Task { await viewModel.regenerateToken(for: bot) } }
                                .tint(.orange)
                        }
                    }
                }

                Section("Как подключить") {
                    Text("Программа бота обращается к \(AppConfig.apiBaseURL.absoluteString)/bot-api с заголовком «Authorization: Bot <токен>»: GET /updates?timeout=25 — новые сообщения, POST /chats/<id>/messages — ответ. Бот пишет только в чаты, куда его добавили или где ему написали первым.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
            }
            .appScreenBackground()
            .navigationTitle("Мои боты")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
            .confirmationDialog(
                "Удалить бота «\(botToDelete?.displayName ?? "")»? Его сообщения тоже удалятся.",
                isPresented: Binding(get: { botToDelete != nil }, set: { if !$0 { botToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Удалить", role: .destructive) {
                    if let bot = botToDelete {
                        Task { await viewModel.delete(bot) }
                    }
                }
            }
            .sheet(item: $viewModel.revealedToken) { revealed in
                BotTokenView(revealed: revealed)
            }
        }
    }
}

private struct BotTokenView: View {
    let revealed: BotsViewModel.RevealedToken
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Токен бота «\(revealed.botName)»").font(.app(.headline))
                Text(revealed.token)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                Button(copied ? "Скопировано" : "Скопировать") {
                    UIPasteboard.general.string = revealed.token
                    copied = true
                }
                .buttonStyle(.borderedProminent)
                Text("Сохраните токен сейчас: он показывается один раз. Кто знает токен, пишет от имени бота — если он утёк, выпустите новый (свайп по боту).")
                    .font(.app(.footnote))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}
