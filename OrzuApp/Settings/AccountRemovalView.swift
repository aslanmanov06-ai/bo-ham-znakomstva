import SwiftUI

/// Отключить аккаунт на время или удалить навсегда. Удаление — только с паролем, если он есть.
struct AccountRemovalView: View {
    @EnvironmentObject private var authViewModel: AuthViewModel
    @ObservedObject var viewModel: SettingsViewModel
    @State private var password = ""
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    private var settings: AccountSettings? { viewModel.settings }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                pauseCard
                deleteCard
                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage).font(.app(.footnote)).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("Аккаунт")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Удалить аккаунт навсегда? Анкета, пары и переписка сразу пропадут для всех, восстановить аккаунт будет нельзя.",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Удалить навсегда", role: .destructive) { delete() }
        }
    }

    private var pauseCard: some View {
        let deactivated = settings?.deactivated == true
        return VStack(alignment: .leading, spacing: 12) {
            header(deactivated ? "Аккаунт отключён" : "Отключить на время", systemImage: "pause.circle.fill", color: .champagne)
            Text(deactivated
                ? "Анкету не видят в ленте и поиске, новые чаты с вами не начать. Включите аккаунт, когда будете готовы."
                : "Анкета пропадёт из ленты и поиска, новые чаты с вами не начать. Переписки, пары и фото сохранятся — вернуться можно в любой момент.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(deactivated ? "Включить аккаунт" : "Отключить аккаунт") {
                Task { await viewModel.setDeactivated(!deactivated) }
            }
            .buttonStyle(deactivated ? AppButtonStyle(kind: .primary) : AppButtonStyle(kind: .secondary))
            .disabled(viewModel.isBusy || settings == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 20)
    }

    private var deleteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            header("Удалить навсегда", systemImage: "trash.fill", color: .red)
            Text("Аккаунт, анкета и фото сразу исчезнут для других, восстановить их будет нельзя. Переписку, фото и видео мы храним ещё год — только для разбора жалоб и запросов по закону, — затем удаляем безвозвратно.")
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DataExportButton()
                .buttonStyle(.plain)
            if settings?.hasPassword == true {
                AppField(systemImage: "key.fill") {
                    SecureField("Пароль для подтверждения", text: $password)
                        .textContentType(.password)
                }
            }
            if let deleteError {
                Text(deleteError).font(.app(.footnote)).foregroundStyle(.red)
            }
            Button {
                confirmDelete = true
            } label: {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Text("Удалить аккаунт")
                }
            }
            .buttonStyle(DestructiveButtonStyle())
            .disabled(!canDelete)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 20)
    }

    private var canDelete: Bool {
        guard let settings, !isDeleting else { return false }
        return !settings.hasPassword || !password.isEmpty
    }

    private func header(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(title).font(.app(.headline))
        }
    }

    private func delete() {
        isDeleting = true
        deleteError = nil
        Task {
            defer { isDeleting = false }
            do {
                try await authViewModel.deleteAccount(password: settings?.hasPassword == true ? password : nil)
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }
}

/// Кнопка необратимого действия: красная заливка вместо фирменного градиента.
private struct DestructiveButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.app(.body, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight)
            .background(Capsule().fill(Color.red))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
