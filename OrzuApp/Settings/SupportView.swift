import SwiftUI

/// Мои обращения в поддержку и ответы на них. Ответ приходит push-уведомлением и появляется здесь.
struct SupportView: View {
    @State private var tickets: [SupportTicket] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showNewTicket = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 56, height: 56)
                        .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    Text("Чем помочь?").font(.display(.title3))
                    Text("Ответ придёт уведомлением и появится здесь.")
                        .font(.app(.subheadline))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)

                Button { showNewTicket = true } label: {
                    Label("Написать в поддержку", systemImage: "paperplane.fill")
                }
                .buttonStyle(.appPrimary)

                if !tickets.isEmpty {
                    Text("МОИ ОБРАЩЕНИЯ")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                        .padding(.top, 6)
                    ForEach(tickets) { ticket in
                        ticketCard(ticket)
                    }
                } else if isLoading {
                    ProgressView().padding(.top, 20)
                }

                if let errorMessage {
                    Text(errorMessage).font(.app(.footnote)).foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(AppBackground())
        .navigationTitle("Поддержка")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showNewTicket) {
            NavigationStack {
                NewSupportTicketView { ticket in
                    tickets.insert(ticket, at: 0)
                }
            }
        }
    }

    private func ticketCard(_ ticket: SupportTicket) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ticket.category.title).font(.app(.subheadline, weight: .semibold))
                Spacer()
                if ticket.reply != nil {
                    statusPill("Ответили", color: .champagne, background: .champagneSoft)
                } else {
                    statusPill("Ждёт ответа", color: .secondary, background: .appElevated)
                }
            }
            Text(ticket.text)
                .font(.app(.subheadline))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let reply = ticket.reply {
                (Text("Поддержка: ").font(.app(.subheadline, weight: .semibold)).foregroundColor(.brand) + Text(reply).font(.app(.subheadline)))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.brandSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text((ticket.repliedAt ?? ticket.createdAt).formatted(.dateTime.day().month().hour().minute()))
                .font(.app(.caption))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 20, padding: 14)
    }

    private func statusPill(_ title: String, color: Color, background: Color) -> some View {
        Text(title)
            .font(.app(.caption, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(background, in: Capsule())
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            tickets = try await APIClient.shared.fetchSupportTickets()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Новое обращение: тема и описание. Границы длины — те же, что проверяет сервер.
struct NewSupportTicketView: View {
    let onSent: (SupportTicket) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: SupportCategory?
    @State private var text = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private static let minLength = 10
    private static let maxLength = 2000

    var body: some View {
        Form {
            Section("Тема") {
                FlowChips(options: SupportCategory.allCases, selection: $category)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
            }
            Section {
                TextField("Опишите подробно — так ответим быстрее", text: $text, axis: .vertical)
                    .lineLimit(5...12)
                    .onChange(of: text) { _, value in
                        if value.count > Self.maxLength { text = String(value.prefix(Self.maxLength)) }
                    }
            } header: {
                Text("Что случилось")
            } footer: {
                Text("\(text.count) / \(Self.maxLength)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Section {
                Label {
                    Text("Если вам угрожают прямо сейчас — нажмите SOS в разделе «Безопасность», это быстрее.")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "shield.lefthalf.filled").foregroundStyle(Color.champagne)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .appScreenBackground()
        .navigationTitle("Новое обращение")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isSending {
                    ProgressView()
                } else {
                    Button("Отправить", action: send).disabled(!canSend)
                }
            }
        }
        .interactiveDismissDisabled(!text.isEmpty)
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        category != nil && trimmedText.count >= Self.minLength
    }

    private func send() {
        guard let category else { return }
        isSending = true
        errorMessage = nil
        Task {
            defer { isSending = false }
            do {
                onSent(try await APIClient.shared.createSupportTicket(category: category, text: trimmedText))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Темы обращения чипами в несколько строк — выбрать можно одну.
private struct FlowChips: View {
    let options: [SupportCategory]
    @Binding var selection: SupportCategory?

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { option in
                let isSelected = selection == option
                Button { selection = option } label: {
                    Text(option.title)
                        .font(.app(.subheadline, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule().fill(.brandFill)
                            } else {
                                Capsule().fill(Color.appElevated)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }
}
