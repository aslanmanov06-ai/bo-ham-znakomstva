import SwiftUI

/// Где выполнен вход: чужое устройство можно завершить, а если что-то не так — выйти везде.
struct SessionsView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var sessions: [AccountSession] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var sessionPendingRevoke: AccountSession?
    @State private var confirmLogoutEverywhere = false

    var body: some View {
        Form {
            if let current = sessions.first(where: \.current) {
                Section {
                    row(current)
                }
            }

            let others = sessions.filter { !$0.current }
            if !others.isEmpty {
                Section {
                    ForEach(others) { session in
                        row(session)
                    }
                } header: {
                    Text("Другие устройства")
                } footer: {
                    Text("Не узнаёте устройство — завершите сеанс и смените пароль. На завершённом устройстве придётся войти заново.")
                }
            } else if !isLoading {
                Section {
                } footer: {
                    Text("Больше нигде не выполнен вход.")
                }
            }

            if isLoading && sessions.isEmpty {
                ProgressView().frame(maxWidth: .infinity)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Section {
                Button("Выйти на всех устройствах", role: .destructive) { confirmLogoutEverywhere = true }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Включая этот телефон.")
            }
        }
        .appScreenBackground()
        .navigationTitle("Активные сеансы")
        .task { await load() }
        .refreshable { await load() }
        .confirmationDialog(
            "Завершить сеанс на «\(sessionPendingRevoke?.deviceName ?? "устройстве")»?",
            isPresented: Binding(get: { sessionPendingRevoke != nil }, set: { if !$0 { sessionPendingRevoke = nil } }),
            titleVisibility: .visible,
            presenting: sessionPendingRevoke
        ) { session in
            Button("Завершить", role: .destructive) { Task { await revoke(session) } }
        }
        .confirmationDialog("Выйти на всех устройствах?", isPresented: $confirmLogoutEverywhere, titleVisibility: .visible) {
            Button("Выйти везде", role: .destructive) { Task { await authViewModel.logoutEverywhere() } }
        }
    }

    private func row(_ session: AccountSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: Self.symbol(for: session.deviceName))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(session.current ? Color.brand : Color.champagne)
                .frame(width: 38, height: 38)
                .background((session.current ? Color.brand : Color.champagne).opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceName ?? "Неизвестное устройство").font(.app(.body, weight: .semibold))
                Text(subtitle(for: session)).font(.app(.caption)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if session.current {
                Text("Это устройство")
                    .font(.app(.caption, weight: .semibold))
                    .foregroundStyle(Color.brand)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Color.brandSoft, in: Capsule())
            } else {
                Button("Завершить") { sessionPendingRevoke = session }
                    .font(.app(.subheadline))
                    .foregroundStyle(.red)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(for session: AccountSession) -> String {
        let signedIn = "вход \(session.createdAt.formatted(.dateTime.day().month()))"
        if session.current { return "Сейчас · \(signedIn)" }
        return "\(session.lastUsedAt.formatted(.relative(presentation: .named))) · \(signedIn)"
    }

    /// deviceName приходит из заголовка устройства: iPhone, iPad или веб-админка.
    private static func symbol(for deviceName: String?) -> String {
        let name = deviceName?.lowercased() ?? ""
        if name.contains("ipad") { return "ipad" }
        if name.contains("iphone") { return "iphone" }
        if name.contains("web") || name.contains("mac") { return "laptopcomputer" }
        return "iphone"
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            sessions = try await APIClient.shared.fetchSessions()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revoke(_ session: AccountSession) async {
        do {
            try await APIClient.shared.revokeSession(id: session.id)
            sessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
