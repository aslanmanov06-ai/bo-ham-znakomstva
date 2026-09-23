import SwiftUI

struct AttachmentImageView: View {
    let attachment: Attachment
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if failed {
                Label("Не удалось загрузить фото", systemImage: "exclamationmark.triangle")
                    .font(.app(.footnote))
                    .padding(8)
            } else {
                ProgressView()
                    .frame(width: 160, height: 120)
            }
        }
        .frame(maxWidth: 240, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .task(id: attachment.id) {
            do {
                let data = try await AttachmentLoader.shared.data(for: attachment.id)
                image = UIImage(data: data)
                failed = image == nil
            } catch {
                failed = true
            }
        }
    }
}

struct AttachmentFileView: View {
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.fill")
                .font(.app(.title2))
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.fileName)
                    .lineLimit(1)
                Text(attachment.formattedSize)
                    .font(.app(.caption))
                    .opacity(0.7)
            }
        }
    }
}
