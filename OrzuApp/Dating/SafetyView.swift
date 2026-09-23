import SwiftUI

/// Безопасность: доверенные контакты и тревожная кнопка. Контактам уходит геопозиция, пока тревога открыта.
struct SafetyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var contacts: [User] = []
    @State private var alert: SosAlert?
    @State private var emergencyNumbers: [EmergencyNumber] = []
    @State private var isBusy = false
    @State private var errorMessage: String?
    @State private var showContactSearch = false
    @State private var confirmSos = false

    var body: some View {
        List {
            Section {
                sosCard
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                if contacts.isEmpty {
                    Text("Добавьте до \(DatingLimits.maxTrustedContacts) человек, которым уйдёт ваша геопозиция по SOS.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                }
                ForEach(contacts) { contact in
                    HStack {
                        AvatarView(avatarUrl: contact.avatarUrl, name: contact.displayName, size: 44)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(contact.displayName).font(.app(.body, weight: .semibold))
                            Text("@\(contact.username)")
                                .font(.app(.caption))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Убрать", role: .destructive) { remove(contact) }
                            .buttonStyle(.borderless)
                    }
                }
                if contacts.count < DatingLimits.maxTrustedContacts {
                    Button("Добавить контакт", systemImage: "person.badge.plus") { showContactSearch = true }
                        .font(.app(.body, weight: .semibold))
                }
            } header: {
                Text("Доверенные контакты · \(contacts.count) из \(DatingLimits.maxTrustedContacts)")
            } footer: {
                Text("Контакт не узнает, что вы его добавили, пока вы не отправите SOS или не поделитесь встречей.")
            }

            if !emergencyNumbers.isEmpty {
                Section("Экстренные службы") {
                    ForEach(emergencyNumbers) { number in
                        Link(destination: URL(string: "tel://\(number.number)") ?? URL(string: "tel://112")!) {
                            HStack {
                                Text(number.service)
                                Spacer()
                                Text(number.number)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Перед первой встречей").font(.app(.body, weight: .semibold))
                        Text("Встречайтесь в людном месте, скажите близким, куда идёте, и поделитесь встречей в чате пары.")
                            .font(.app(.footnote))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                        .foregroundStyle(Color.champagne)
                }
            }
        }
        .appScreenBackground()
        .navigationTitle("Безопасность")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Закрыть") { dismiss() }
            }
        }
        .task { await loadContacts() }
        .sheet(isPresented: $showContactSearch) {
            NavigationStack {
                TrustedContactSearchView { user in
                    add(user)
                }
            }
        }
        .confirmationDialog("Отправить SOS?", isPresented: $confirmSos, titleVisibility: .visible) {
            Button("Отправить SOS", role: .destructive) { raiseSos() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Доверенные контакты и модераторы получат вашу геопозицию.")
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    /// Тревога — первым блоком и крупно: в опасности её не должно быть нужно искать.
    private var sosCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "sos")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Self.alarmRed, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(isAlertOpen ? "Тревога отправлена" : "Тревога SOS")
                        .font(.display(.headline))
                    Text(isAlertOpen ? "Геопозиция ушла доверенным контактам и модераторам." : "Геопозиция уйдёт доверенным контактам и модераторам")
                        .font(.app(.footnote))
                        .foregroundStyle(.white.opacity(0.75))
                }
            }
            if let alert, alert.status == .open {
                HStack(spacing: 10) {
                    Button("Обновить место") { updateLocation(alertId: alert.id) }
                        .buttonStyle(.appSecondary)
                    Button("Я в безопасности") { close(alertId: alert.id) }
                        .buttonStyle(.appPrimary)
                }
            } else {
                Button { confirmSos = true } label: {
                    Text("SOS — мне нужна помощь")
                        .font(.app(.body, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: AppMetrics.buttonHeight)
                        .background(Self.alarmRed, in: Capsule())
                        .shadow(color: Self.alarmRed.opacity(0.35), radius: 12, y: 6)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .foregroundStyle(.white)
        .disabled(isBusy)
        .padding(18)
        .background(
            LinearGradient(colors: [Color(rgb: 0x5A1733), Color(rgb: 0x2A0F1C)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: AppMetrics.cardRadius, style: .continuous)
        )
    }

    private var isAlertOpen: Bool {
        alert?.status == .open
    }

    /// Красный тревоги — не фирменный гранат: SOS должен отличаться от лайка с первого взгляда.
    private static let alarmRed = Color(rgb: 0xFF4D5E)

    private func loadContacts() async {
        do {
            contacts = try await APIClient.shared.fetchTrustedContacts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add(_ user: User) {
        Task {
            do {
                try await APIClient.shared.addTrustedContact(userId: user.id)
                await loadContacts()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func remove(_ user: User) {
        Task {
            do {
                try await APIClient.shared.removeTrustedContact(userId: user.id)
                contacts.removeAll { $0.id == user.id }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func raiseSos() {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let location = try await LocationProvider.shared.current()
                let raised = try await APIClient.shared.raiseSos(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    accuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : nil,
                    note: nil,
                    withUserId: nil
                )
                alert = raised.alert
                emergencyNumbers = raised.emergencyNumbers
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateLocation(alertId: String) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let location = try await LocationProvider.shared.current()
                alert = try await APIClient.shared.updateSosLocation(
                    alertId: alertId,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    accuracyM: location.horizontalAccuracy > 0 ? location.horizontalAccuracy : nil
                )
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func close(alertId: String) {
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                alert = try await APIClient.shared.closeSos(alertId: alertId)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Поиск человека для доверенного контакта — по username или имени, как в «Новом чате».
struct TrustedContactSearchView: View {
    let onPick: (User) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var users: [User] = []
    @State private var errorMessage: String?

    var body: some View {
        List(users) { user in
            Button {
                onPick(user)
                dismiss()
            } label: {
                HStack {
                    AvatarView(avatarUrl: user.avatarUrl, name: user.displayName, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(user.displayName)
                            .foregroundStyle(.primary)
                        Text("@\(user.username)")
                            .font(.app(.caption))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .appScreenBackground()
        .searchable(text: $query, prompt: "Имя или username")
        .navigationTitle("Доверенный контакт")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
        }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.count >= 2 else {
                users = []
                return
            }
            do {
                users = try await APIClient.shared.searchUsers(query: text)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Ошибка", isPresented: .constant(errorMessage != nil)) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }
}
