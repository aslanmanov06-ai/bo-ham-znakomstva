import AVFoundation

/// Воспроизведение голосовых: одновременно играет одно — новое останавливает предыдущее, как в Telegram.
@MainActor
final class VoicePlayer: NSObject, ObservableObject {
    static let shared = VoicePlayer()

    /// Вложение, которое сейчас играет или стоит на паузе.
    @Published private(set) var activeId: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var loadingId: String?
    /// 0…1 для полосы прогресса.
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private static let tickInterval: TimeInterval = 0.1

    /// Нажатие на своё — пауза/продолжение, на другое — переключение.
    func toggle(_ attachment: Attachment) async throws {
        if activeId == attachment.id, let player {
            if player.isPlaying { pause() } else { resume() }
            return
        }
        stop()
        loadingId = attachment.id
        defer { if loadingId == attachment.id { loadingId = nil } }

        let data = try await AttachmentLoader.shared.data(for: attachment.id)
        // Пока качалось, пользователь мог нажать на другое голосовое — это уже неактуально.
        guard loadingId == attachment.id else { return }

        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        let player = try AVAudioPlayer(data: data)
        player.delegate = self
        self.player = player
        activeId = attachment.id
        resume()
    }

    func stop() {
        player?.stop()
        player = nil
        activeId = nil
        isPlaying = false
        progress = 0
        stopTimer()
    }

    private func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    private func resume() {
        guard let player, player.play() else { return }
        isPlaying = true
        timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func tick() {
        guard let player, player.duration > 0 else { return }
        progress = player.currentTime / player.duration
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension VoicePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            // Событие могло прийти от уже заменённого плеера — новое голосовое не трогаем.
            guard let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.stop()
        }
    }
}
