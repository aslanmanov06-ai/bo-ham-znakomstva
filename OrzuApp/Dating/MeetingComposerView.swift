import SwiftUI

/// Приглашение на встречу: время, место и пожелание. Перенос заполняет форму прежними местом и заметкой.
struct MeetingComposerView: View {
    let editing: MeetingEditing
    let partnerName: String
    let partnerPhotoId: String?
    let onSubmit: (Date, String, String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startsAt = Date().addingTimeInterval(60 * 60)
    @State private var place = ""
    @State private var note = ""
    @State private var isSending = false

    // Те же границы, что проверяет сервер: не раньше чем через 15 минут и не дальше 60 дней.
    private let minLead: TimeInterval = 15 * 60
    private let maxAhead: TimeInterval = 60 * 24 * 60 * 60

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    DatingPhotoView(attachmentId: partnerPhotoId, cornerRadius: 22)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Встреча с").font(.app(.footnote)).foregroundStyle(.secondary)
                        Text(partnerName).font(.display(.headline))
                    }
                }
                .listRowBackground(Color.clear)
            }
            Section {
                DatePicker("Начало", selection: $startsAt, in: Date().addingTimeInterval(minLead)...Date().addingTimeInterval(maxAhead))
            } header: {
                Label("Когда", systemImage: "calendar")
            }
            Section {
                TextField("Кафе, парк, адрес", text: $place)
            } header: {
                Label("Где", systemImage: "mappin.and.ellipse")
            }
            Section {
                TextField("Пожелание или уточнение", text: $note, axis: .vertical)
                    .lineLimit(2...5)
            } header: {
                Label("Заметка", systemImage: "text.quote")
            }
            Section {
                Label("Первые встречи — в людных местах. Расскажите близким, куда идёте: назначенной встречей можно поделиться с доверенными контактами.", systemImage: "shield.lefthalf.filled")
                    .font(.app(.footnote))
                    .foregroundStyle(Color.champagne)
                    .listRowBackground(Color.champagneSoft)
            }
        }
        .appScreenBackground()
        .navigationTitle(isReschedule ? "Другое время" : "Встреча")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Отправить", action: submit)
                    .font(.app(.body, weight: .semibold))
                    .disabled(isSending || place.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .task {
            // Перенос: место и заметка по умолчанию остаются прежними — меняют обычно только время.
            if case .reschedule(let meeting) = editing.mode {
                place = meeting.place
                note = meeting.note
                startsAt = max(meeting.startsAt, Date().addingTimeInterval(minLead))
            }
        }
    }

    private var isReschedule: Bool {
        if case .reschedule = editing.mode { return true }
        return false
    }

    private func submit() {
        isSending = true
        Task {
            defer { isSending = false }
            let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
            await onSubmit(startsAt, place.trimmingCharacters(in: .whitespacesAndNewlines), trimmedNote.isEmpty ? nil : trimmedNote)
            dismiss()
        }
    }
}
