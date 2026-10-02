import AVFoundation
import SwiftUI

// MARK: - Голосовое

struct VoiceMessageView: View {
    let attachment: Attachment
    let isMine: Bool
    let onError: (String) -> Void
    @ObservedObject private var player = VoicePlayer.shared

    private static let barCount = 26

    var body: some View {
        let isActive = player.activeId == attachment.id
        let duration = attachment.durationSec ?? 0
        HStack(spacing: 10) {
            Button {
                Task {
                    do {
                        try await player.toggle(attachment)
                    } catch {
                        onError(String(localized: "Не удалось воспроизвести: \(error.localizedDescription)"))
                    }
                }
            } label: {
                Group {
                    if player.loadingId == attachment.id {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: isActive && player.isPlaying ? "pause.fill" : "play.fill")
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(isMine ? Color.brand : Color.white)
                .frame(width: 40, height: 40)
                .background {
                    if isMine { Circle().fill(Color.white) } else { Circle().fill(.brandFill) }
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive && player.isPlaying ? "Пауза" : "Воспроизвести голосовое")

            VStack(alignment: .leading, spacing: 4) {
                waveform(progress: isActive ? player.progress : 0)
                    .frame(height: 24)
                    .accessibilityHidden(true)
                Text(isActive
                     ? "\(Attachment.formattedDuration(Int(player.currentTime))) / \(Attachment.formattedDuration(duration))"
                     : Attachment.formattedDuration(duration))
                    .font(.app(size: 11).monospacedDigit())
                    .opacity(0.8)
                    .contentTransition(.numericText())
            }
            .frame(width: 150, alignment: .leading)

            Button { player.cycleRate() } label: {
                Text(Self.rateLabel(player.rate))
                    .font(.app(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(isMine ? Color.white : Color.brand)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(isMine ? Color.white.opacity(0.22) : Color.brandSoft, in: Capsule())
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Скорость \(Self.rateLabel(player.rate))")
        }
    }

    /// Столбики «волны». Настоящей громкости в сообщении нет — высоты стабильны для каждого голосового (по его id).
    private func waveform(progress: Double) -> some View {
        let heights = Self.barHeights(seed: attachment.id, count: Self.barCount)
        let played = isMine ? Color.white : Color.brand
        let rest = isMine ? Color.white.opacity(0.4) : Color.secondary.opacity(0.45)
        return HStack(alignment: .center, spacing: 2) {
            ForEach(heights.indices, id: \.self) { index in
                Capsule()
                    .fill(Double(index) / Double(heights.count) < progress ? played : rest)
                    .frame(width: 3, height: heights[index])
            }
        }
        .animation(.linear(duration: 0.1), value: progress)
    }

    static func rateLabel(_ rate: Float) -> String {
        rate == 1 ? "1×" : rate == 2 ? "2×" : "1,5×"
    }

    /// 6…24 pt, псевдослучайно, но одинаково для одного id (FNV-1a + xorshift).
    static func barHeights(seed: String, count: Int) -> [CGFloat] {
        var state: UInt64 = 0xcbf29ce484222325
        for byte in seed.utf8 { state = (state ^ UInt64(byte)) &* 0x100000001b3 }
        return (0..<count).map { index in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            // По краям пониже — волна «дышит» к середине.
            let edge = 1 - abs(Double(index) / Double(max(count - 1, 1)) * 2 - 1) * 0.35
            return CGFloat(6 + Double(state % 19) * edge)
        }
    }
}

// MARK: - Видеосообщение («кружок»)

struct VideoNoteView: View {
    let attachment: Attachment
    @State private var poster: UIImage?
    @State private var player: AVPlayer?
    @State private var isLoadingVideo = false
    @State private var isPlaying = false
    @State private var failed = false

    static let diameter: CGFloat = 200

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
            } else if let poster {
                Image(uiImage: poster).resizable().scaledToFill()
            }
            if failed {
                Image(systemName: "exclamationmark.triangle").font(.app(.title))
            } else if isLoadingVideo {
                ProgressView()
            } else if !isPlaying {
                Image(systemName: "play.fill")
                    .font(.app(.title2))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(.ultraThinMaterial, in: Circle())
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .background(Color.black.opacity(0.15))
        .clipShape(Circle())
        .overlay(alignment: .bottom) {
            Text(Attachment.formattedDuration(attachment.durationSec ?? 0))
                .font(.app(.caption2).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 10)
        }
        .contentShape(Circle())
        .onTapGesture(perform: togglePlayback)
        .accessibilityElement()
        .accessibilityLabel("Видеосообщение")
        .accessibilityAddTraits(.isButton)
        .task(id: attachment.id) {
            // Без обложки (старый ролик) остаётся тёмный круг с кнопкой — ролик всё равно включится по нажатию.
            poster = (try? await AttachmentLoader.shared.poster(for: attachment.id)).flatMap(UIImage.init(data:))
        }
        .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { notification in
            guard let player, notification.object as? AVPlayerItem === player.currentItem else { return }
            player.seek(to: .zero)
            isPlaying = false
        }
        .onDisappear {
            player?.pause()
            isPlaying = false
        }
    }

    private func togglePlayback() {
        guard let player else {
            loadAndPlay()
            return
        }
        if isPlaying {
            player.pause()
        } else {
            VoicePlayer.shared.stop()
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player.play()
        }
        isPlaying.toggle()
    }

    /// Ролик качается только по нажатию: в ленте чата видна обложка, и трафик не уходит на то, что не посмотрят.
    private func loadAndPlay() {
        guard !isLoadingVideo else { return }
        isLoadingVideo = true
        failed = false
        Task {
            defer { isLoadingVideo = false }
            do {
                // AVPlayer играет только с диска или по URL, а скачивание требует токена — кладём во временный файл.
                let url = try await AttachmentLoader.shared.temporaryFileURL(for: attachment)
                player = AVPlayer(url: url)
                togglePlayback()
            } catch {
                failed = true
            }
        }
    }
}

private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ view: PlayerUIView, context: Context) {
        view.playerLayer.player = player
    }

    final class PlayerUIView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

// MARK: - Фото с таймером

struct TimedPhotoView: View {
    let attachment: Attachment
    let state: TimedPhotoState
    let viewTimerSec: Int
    let onOpen: () -> Void

    var body: some View {
        switch state {
        case .own(let viewed):
            VStack(alignment: .leading, spacing: 4) {
                AttachmentImageView(attachment: attachment)
                    .overlay(alignment: .topTrailing) { timerBadge.padding(6) }
                Label(viewed ? "Просмотрено" : "Не просмотрено", systemImage: viewed ? "eye" : "eye.slash")
                    .font(.app(.caption))
                    .opacity(0.8)
            }
        case .unopened, .open:
            Button(action: onOpen) {
                VStack(spacing: 8) {
                    Image(systemName: "flame.fill").font(.app(.largeTitle))
                    Text("Фото · \(viewTimerSec) с").font(.app(.subheadline, weight: .bold))
                    Text(state == .unopened ? "Нажмите, чтобы посмотреть" : "Нажмите, чтобы досмотреть")
                        .font(.app(.caption))
                        .opacity(0.8)
                }
                .frame(width: 200, height: 150)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        case .expired:
            Label("Фото просмотрено", systemImage: "flame")
                .font(.app(.subheadline))
                .opacity(0.8)
        }
    }

    private var timerBadge: some View {
        Label("\(viewTimerSec) с", systemImage: "timer")
            .font(.app(.caption2, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.5), in: Capsule())
    }
}

/// Что показать на весь экран после POST …/open.
struct TimedPhotoPresentation: Identifiable {
    let id: String
    let attachmentId: String
    let viewTimerSec: Int
    let expiresAt: Date
}

/// Фото видно, пока идёт таймер; закрывается само и при сворачивании приложения — досмотреть можно, пока время не вышло.
struct TimedPhotoViewer: View {
    let presentation: TimedPhotoPresentation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else if failed {
                Label("Не удалось загрузить фото", systemImage: "exclamationmark.triangle").foregroundStyle(.white)
            } else {
                ProgressView().tint(.white)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.app(.title3, weight: .semibold)).foregroundStyle(.white).padding(12)
                }
                .accessibilityLabel("Закрыть")
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.1)) { context in
                    CountdownRing(remaining: presentation.expiresAt.timeIntervalSince(context.date), total: TimeInterval(presentation.viewTimerSec))
                }
            }
            .padding()
        }
        .task {
            // Не через AttachmentLoader: его кеш держал бы фото в памяти и после истечения таймера.
            do {
                image = UIImage(data: try await APIClient.shared.downloadAttachment(id: presentation.attachmentId))
                failed = image == nil
            } catch {
                failed = true
            }
        }
        .task {
            let remaining = presentation.expiresAt.timeIntervalSinceNow
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            if !Task.isCancelled { dismiss() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { dismiss() }
        }
        .hiddenWhileScreenCaptured()
    }
}

private struct CountdownRing: View {
    let remaining: TimeInterval
    let total: TimeInterval

    var body: some View {
        let clamped = max(0, remaining)
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 3)
            Circle()
                .trim(from: 0, to: total > 0 ? clamped / total : 0)
                .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(clamped.rounded(.up)))")
                .font(.app(.caption).monospacedDigit().bold())
                .foregroundStyle(.white)
        }
        .frame(width: 36, height: 36)
        .accessibilityLabel("Осталось \(Int(clamped.rounded(.up))) секунд")
    }
}

// MARK: - Запись экрана

/// Идёт ли запись, трансляция или AirPlay-повтор экрана. Скриншот так не запретить, а вот видео — закрыть заглушкой.
@MainActor
final class ScreenCaptureMonitor: ObservableObject {
    static let shared = ScreenCaptureMonitor()

    @Published private(set) var isCaptured = false
    private var observer: NSObjectProtocol?

    private init() {
        isCaptured = UIScreen.main.isCaptured
        observer = NotificationCenter.default.addObserver(forName: UIScreen.capturedDidChangeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in ScreenCaptureMonitor.shared.update() }
        }
    }

    private func update() {
        isCaptured = UIScreen.main.isCaptured
    }
}

/// Фото с таймером и секретная переписка не должны оказаться в чужой записи экрана.
private struct ScreenCaptureShield: ViewModifier {
    let isEnabled: Bool
    @ObservedObject private var monitor = ScreenCaptureMonitor.shared

    func body(content: Content) -> some View {
        content.overlay {
            if isEnabled && monitor.isCaptured {
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 10) {
                        Image(systemName: "eye.slash").font(.system(size: 34, weight: .semibold))
                        Text("Идёт запись экрана — содержимое скрыто")
                            .font(.app(.body, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white)
                    .padding(24)
                }
            }
        }
    }
}

extension View {
    func hiddenWhileScreenCaptured(_ isEnabled: Bool = true) -> some View {
        modifier(ScreenCaptureShield(isEnabled: isEnabled))
    }
}

// MARK: - Обработка на сервере

/// Видео или голосовое ещё перекодируется на сервере: пузырь заменится сам, когда придёт message.updated.
struct ProcessingAttachmentView: View {
    let kind: AttachmentKind

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.app(.subheadline, weight: .semibold))
                Text("Обрабатывается — появится через минуту")
                    .font(.app(.caption))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch kind {
        case .voice: return String(localized: "Голосовое сообщение")
        case .videoNote: return String(localized: "Видеосообщение")
        default: return String(localized: "Видео")
        }
    }
}
