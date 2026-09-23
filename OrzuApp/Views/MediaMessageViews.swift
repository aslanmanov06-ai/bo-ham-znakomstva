import AVFoundation
import SwiftUI

// MARK: - Голосовое

struct VoiceMessageView: View {
    let attachment: Attachment
    let isMine: Bool
    let onError: (String) -> Void
    @ObservedObject private var player = VoicePlayer.shared

    private static let width: CGFloat = 180

    var body: some View {
        let isActive = player.activeId == attachment.id
        HStack(spacing: 10) {
            Button {
                Task {
                    do {
                        try await player.toggle(attachment)
                    } catch {
                        onError("Не удалось воспроизвести: \(error.localizedDescription)")
                    }
                }
            } label: {
                Group {
                    if player.loadingId == attachment.id {
                        ProgressView().tint(isMine ? .white : nil)
                    } else {
                        Image(systemName: isActive && player.isPlaying ? "pause.fill" : "play.fill")
                    }
                }
                .font(.app(.title3))
                .frame(width: 36, height: 36)
                .background(isMine ? Color.white.opacity(0.25) : Color.accentColor.opacity(0.15), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isActive && player.isPlaying ? "Пауза" : "Воспроизвести голосовое")

            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: isActive ? player.progress : 0)
                    .tint(isMine ? .white : .accentColor)
                Text(Attachment.formattedDuration(attachment.durationSec ?? 0))
                    .font(.app(.caption).monospacedDigit())
                    .opacity(0.8)
            }
            .frame(width: Self.width)
        }
    }
}

// MARK: - Видеосообщение («кружок»)

struct VideoNoteView: View {
    let attachment: Attachment
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var failed = false

    static let diameter: CGFloat = 200

    var body: some View {
        ZStack {
            if let player {
                PlayerLayerView(player: player)
            } else if failed {
                Image(systemName: "exclamationmark.triangle").font(.app(.title))
            } else {
                ProgressView()
            }
            if player != nil, !isPlaying {
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
            do {
                // AVPlayer играет только с диска или по URL, а скачивание требует токена — кладём во временный файл.
                let url = try await AttachmentLoader.shared.temporaryFileURL(for: attachment)
                player = AVPlayer(url: url)
            } catch {
                failed = true
            }
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
        guard let player else { return }
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
