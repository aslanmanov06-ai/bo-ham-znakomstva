import Foundation

@MainActor
final class BotsViewModel: ObservableObject {
    @Published var bots: [Bot] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Только что выданный токен — показываем один раз, сервер хранит лишь его хеш.
    @Published var revealedToken: RevealedToken?

    struct RevealedToken: Identifiable {
        let botName: String
        let token: String
        var id: String { token }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bots = try await APIClient.shared.fetchMyBots()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(username: String, displayName: String) async -> Bool {
        do {
            let bot = try await APIClient.shared.createBot(username: username, displayName: displayName)
            bots.append(bot)
            if let token = bot.token {
                revealedToken = RevealedToken(botName: bot.displayName, token: token)
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func regenerateToken(for bot: Bot) async {
        do {
            let token = try await APIClient.shared.regenerateBotToken(botId: bot.id)
            revealedToken = RevealedToken(botName: bot.displayName, token: token)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ bot: Bot) async {
        do {
            try await APIClient.shared.deleteBot(botId: bot.id)
            bots.removeAll { $0.id == bot.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
