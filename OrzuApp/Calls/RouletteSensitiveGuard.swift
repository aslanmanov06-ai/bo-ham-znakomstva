import CoreVideo
import Foundation
import SensitiveContentAnalysis
import WebRTC
import os

/// Откровенное видео собеседника в рулетке: iPhone сам, на устройстве, смотрит входящие кадры (SensitiveContentAnalysis)
/// и говорит, что видео лучше скрыть. Кадры никуда не уходят — ни нам, ни Apple. Работает, только если у человека
/// включены «Предупреждения о деликатном контенте» (Настройки → Конфиденциальность) или Экранное время ребёнка;
/// иначе анализатор не создаётся и рулетка работает как прежде.
@available(iOS 26.0, *)
final class RouletteSensitiveGuard: NSObject, RTCVideoRenderer, @unchecked Sendable {
    /// Кадров в секунду на проверку: этого хватает, чтобы заметить, и не грузит процессор во время HD-разговора.
    private static let framesPerSecond: Double = 2

    private let analyzer: SCVideoStreamAnalyzer
    private let queue = DispatchQueue(label: "com.orzuapp.roulette.sensitive")
    private let logger = Logger(subsystem: "com.orzuapp.messenger", category: "Roulette")
    private weak var track: RTCVideoTrack?
    private var lastAnalyzedAt = Date.distantPast
    private var watcher: Task<Void, Never>?

    /// nil — анализ на этом iPhone выключен или недоступен.
    init?(participant: String, track: RTCVideoTrack, onChange: @escaping @MainActor (_ hide: Bool, _ muteAudio: Bool) -> Void) {
        guard SCSensitivityAnalyzer().analysisPolicy != .disabled,
              let analyzer = try? SCVideoStreamAnalyzer(participantUUID: participant, streamDirection: .incoming)
        else { return nil }
        self.analyzer = analyzer
        self.track = track
        super.init()
        watcher = Task { @MainActor [analyzer, logger] in
            do {
                for try await analysis in analyzer.analysisChanges {
                    onChange(analysis.shouldInterruptVideo || analysis.isSensitive, analysis.shouldMuteAudio)
                }
            } catch {
                logger.error("Анализ видео рулетки: \(error.localizedDescription, privacy: .public)")
            }
        }
        track.add(self)
    }

    /// Человек сам решил смотреть дальше — анализ продолжается со следующих кадров.
    func continueStream() {
        queue.async { [analyzer] in analyzer.continueStream() }
    }

    func stop() {
        track?.remove(self)
        track = nil
        watcher?.cancel()
        queue.async { [analyzer] in analyzer.endAnalysis() }
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAnalyzedAt) >= 1 / Self.framesPerSecond else { return }
        lastAnalyzedAt = now
        guard let pixelBuffer = Self.pixelBuffer(of: frame.buffer) else { return }
        queue.async { [analyzer] in analyzer.analyze(pixelBuffer) }
    }

    /// Аппаратный декодер (H.264) отдаёт CVPixelBuffer; программный (VP8) — I420, его перекладываем в NV12.
    private static func pixelBuffer(of buffer: RTCVideoFrameBuffer) -> CVPixelBuffer? {
        if let native = buffer as? RTCCVPixelBuffer { return native.pixelBuffer }
        let i420 = buffer.toI420()
        var output: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary
        guard CVPixelBufferCreate(nil, Int(i420.width), Int(i420.height), kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attributes, &output) == kCVReturnSuccess,
              let output
        else { return nil }
        CVPixelBufferLockBaseAddress(output, [])
        defer { CVPixelBufferUnlockBaseAddress(output, []) }
        guard let lumaBase = CVPixelBufferGetBaseAddressOfPlane(output, 0),
              let chromaBase = CVPixelBufferGetBaseAddressOfPlane(output, 1)
        else { return nil }
        let luma = lumaBase.assumingMemoryBound(to: UInt8.self)
        let lumaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 0)
        for row in 0..<Int(i420.height) {
            (luma + row * lumaStride).update(from: i420.dataY + row * Int(i420.strideY), count: Int(i420.width))
        }
        let chroma = chromaBase.assumingMemoryBound(to: UInt8.self)
        let chromaStride = CVPixelBufferGetBytesPerRowOfPlane(output, 1)
        for row in 0..<Int(i420.chromaHeight) {
            let line = chroma + row * chromaStride
            let u = i420.dataU + row * Int(i420.strideU)
            let v = i420.dataV + row * Int(i420.strideV)
            for column in 0..<Int(i420.chromaWidth) {
                line[column * 2] = u[column]
                line[column * 2 + 1] = v[column]
            }
        }
        return output
    }
}
