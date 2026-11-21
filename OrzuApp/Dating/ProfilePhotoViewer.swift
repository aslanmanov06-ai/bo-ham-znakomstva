import SwiftUI

/// Фото анкеты на весь экран: листаются свайпом, щипок — увеличить, двойное касание — увеличить и вернуть.
/// В карточке анкеты фото обрезано под рамку — здесь оно видно целиком.
struct ProfilePhotoViewer: View {
    let photoIds: [String]
    /// Общий с карточкой анкеты: закрыв просмотр, человек остаётся на том же фото.
    @Binding var index: Int
    /// Чужой скрытый альбом: фото не попадают в снимок и запись экрана.
    var isPrivate = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photoIds.enumerated()), id: \.element) { position, photoId in
                    ZoomablePhoto(attachmentId: photoId)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .protectedFromScreenshots(isPrivate)
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .accessibilityLabel("Закрыть")
                Spacer()
                if photoIds.count > 1 {
                    Text(verbatim: "\(index + 1) / \(photoIds.count)")
                        .font(.app(.subheadline, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.45), in: Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)
        }
        .statusBarHidden()
    }
}

/// Одно фото с увеличением. Пока оно не увеличено, свайп достаётся листанию страниц.
private struct ZoomablePhoto: View {
    let attachmentId: String

    private static let maxScale: CGFloat = 5
    private static let doubleTapScale: CGFloat = 2.5

    @State private var image: UIImage?
    @State private var failed = false
    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(magnify(in: proxy.size))
                        .gesture(pan(in: proxy.size), including: scale > 1 ? .all : .none)
                        .onTapGesture(count: 2) { toggleZoom() }
                        .accessibilityLabel("Фото анкеты")
                } else if failed {
                    Label("Не удалось загрузить фото", systemImage: "photo")
                        .font(.app(.subheadline))
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .task(id: attachmentId) {
            do {
                image = UIImage(data: try await AttachmentLoader.shared.data(for: attachmentId))
                failed = image == nil
            } catch {
                failed = true
            }
        }
        // Перелистнули — следующее возвращение к фото начинается без увеличения.
        .onDisappear { reset() }
    }

    private func magnify(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                scale = min(max(settledScale * value.magnification, 1), Self.maxScale)
                offset = PhotoZoom.clamped(settledOffset, scale: scale, in: size)
            }
            .onEnded { _ in
                settledScale = scale
                settledOffset = offset
                if scale == 1 { reset() }
            }
    }

    private func pan(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let moved = CGSize(width: settledOffset.width + value.translation.width, height: settledOffset.height + value.translation.height)
                offset = PhotoZoom.clamped(moved, scale: scale, in: size)
            }
            .onEnded { _ in settledOffset = offset }
    }

    private func toggleZoom() {
        withAnimation(.easeOut(duration: 0.2)) {
            if scale > 1 {
                reset()
            } else {
                scale = Self.doubleTapScale
                settledScale = Self.doubleTapScale
            }
        }
    }

    private func reset() {
        scale = 1
        settledScale = 1
        offset = .zero
        settledOffset = .zero
    }
}

enum PhotoZoom {
    /// Увеличенное фото нельзя утащить дальше своего края: сдвиг не больше половины «лишнего» размера.
    static func clamped(_ offset: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let maxX = max(size.width * (scale - 1) / 2, 0)
        let maxY = max(size.height * (scale - 1) / 2, 0)
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }
}
