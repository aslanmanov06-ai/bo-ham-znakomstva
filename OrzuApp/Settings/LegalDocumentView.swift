import SwiftUI
import UniformTypeIdentifiers

/// Правила сообщества, политика конфиденциальности или соглашение — тексты с сервера, чтобы править их без обновления приложения.
struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    @State private var document: LegalDocument?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let document {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Редакция от \(Self.versionLabel(document.version))")
                        .font(.app(.footnote))
                        .foregroundStyle(.secondary)
                    ForEach(document.sections, id: \.self) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            if !section.title.isEmpty {
                                Text(section.title).font(.display(.headline))
                            }
                            ForEach(section.paragraphs, id: \.self) { paragraph in
                                Text(paragraph)
                                    .font(.app(.subheadline))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Не удалось открыть", systemImage: "doc.text")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Повторить") { Task { await load() } }
                        .buttonStyle(.appSecondary)
                        .fixedSize()
                }
                .padding(.top, 60)
            } else {
                ProgressView().padding(.top, 60)
            }
        }
        .background(AppBackground())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        errorMessage = nil
        do {
            switch kind {
            case .privacy:
                document = try await APIClient.shared.fetchPrivacyPolicy()
            case .terms:
                document = try await APIClient.shared.fetchTermsOfService()
            case .rules:
                let rules = try await APIClient.shared.fetchCommunityRules()
                let numbered = rules.rules.enumerated().map { "\($0.offset + 1). \($0.element)" }
                document = LegalDocument(version: rules.version, title: kind.title, sections: [.init(title: "", paragraphs: numbered)])
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Версия — дата вида 2026-09-22; не дата — показываем как есть.
    private static func versionLabel(_ version: String) -> String {
        guard let date = versionFormatter.date(from: version) else { return version }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    private static let versionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// «Скачать мои данные»: сервер собирает JSON, человек сохраняет его через системный экран «Файлы».
struct DataExportButton: View {
    @State private var file: DataExportFile?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            load()
        } label: {
            LabeledContent {
                if isLoading {
                    ProgressView()
                } else {
                    Text("JSON")
                }
            } label: {
                SettingsLabel("Скачать мои данные", systemImage: "arrow.down.doc.fill", color: .champagne)
            }
        }
        .tint(.primary)
        .disabled(isLoading)
        .fileExporter(
            isPresented: Binding(get: { file != nil }, set: { if !$0 { file = nil } }),
            document: file,
            contentType: .json,
            defaultFilename: "boham-my-data.json"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Ошибка", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Ок") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                file = DataExportFile(data: try await APIClient.shared.exportMyData())
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct DataExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.json]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
