import AVFoundation
import CoreMedia
import WebRTC

/// Качество видео звонков и рулетки: HD 720p при 30 кадрах/с. Если сеть или процессор не справляются, WebRTC сам
/// снижает разрешение и частоту понемногу (balanced) — картинка становится мягче, но не замирает.
enum VideoQuality {
    static let maxWidth: Int32 = 1280
    static let maxHeight: Int32 = 720
    static let frameRate = 30
    /// Разговор один на один: 2,5 Мбит/с хватает на чёткие 720p30.
    static let oneToOneBitrateBps = 2_500_000
    /// Групповой звонок (mesh): видео уходит каждому участнику отдельно — меньше на каждого, иначе мобильная сеть не вытянет.
    static let groupBitrateBps = 1_000_000

    /// Формат камеры, ближайший к 720p сверху вниз, который держит 30 кадров/с. Форматы у камеры идут от мелких
    /// к крупным, поэтому «первый подходящий» был бы самым мелким (192×144) — выбираем самый крупный в пределах HD.
    static func captureFormat(for camera: AVCaptureDevice) -> (format: AVCaptureDevice.Format, fps: Int)? {
        let best = RTCCameraVideoCapturer.supportedFormats(for: camera)
            .filter { format in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let maxFps = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                return size.width <= maxWidth && size.height <= maxHeight && maxFps >= Double(frameRate)
            }
            .max { area(of: $0) < area(of: $1) }
        guard let best else { return nil }
        return (best, frameRate)
    }

    private static func area(of format: AVCaptureDevice.Format) -> Int {
        let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        return Int(size.width) * Int(size.height)
    }

    /// Потолок битрейта и частоты для отправляемого видео; пока сеть позволяет — держим HD.
    static func configure(_ sender: RTCRtpSender, maxBitrateBps: Int) {
        let parameters = sender.parameters
        for encoding in parameters.encodings {
            encoding.maxBitrateBps = NSNumber(value: maxBitrateBps)
            encoding.maxFramerate = NSNumber(value: frameRate)
        }
        parameters.degradationPreference = NSNumber(value: RTCDegradationPreference.balanced.rawValue)
        sender.parameters = parameters
    }
}
