import Accelerate
import CoreVideo
import WebRTC

/// Фронтальная камера «как в зеркале» — и в своём превью, и у собеседника (как в Android и в вебе). Кадр
/// отражается до кодирования, поэтому собеседник получает уже отражённое видео, а превью показывает дорожку как есть.
///
/// RTCCameraVideoCapturer держит делегата слабо — владелец (CallManager, RouletteVideoEngine) хранит его сам.
final class MirroringCapturerDelegate: NSObject, RTCVideoCapturerDelegate, @unchecked Sendable {
    private let target: RTCVideoCapturerDelegate
    private let mirror = PixelBufferMirror()
    private let lock = NSLock()
    private var mirrored = true

    /// Фронтальная — отражаем, основная — как есть. Кадры приходят в очереди камеры, поэтому под замком.
    var isMirrored: Bool {
        get { lock.withLock { mirrored } }
        set { lock.withLock { mirrored = newValue } }
    }

    init(target: RTCVideoCapturerDelegate) {
        self.target = target
    }

    func capturer(_ capturer: RTCVideoCapturer, didCapture frame: RTCVideoFrame) {
        guard
            isMirrored,
            let buffer = frame.buffer as? RTCCVPixelBuffer,
            // Кадр в портрете лежит в буфере боком (поворот 90 или 270): «слева направо» на экране — «сверху вниз» в буфере.
            let reflected = mirror.mirrored(buffer.pixelBuffer, vertically: frame.rotation.rawValue % 180 != 0)
        else {
            target.capturer(capturer, didCapture: frame)
            return
        }
        target.capturer(capturer, didCapture: RTCVideoFrame(buffer: RTCCVPixelBuffer(pixelBuffer: reflected), rotation: frame.rotation, timeStampNs: frame.timeStampNs))
    }
}

/// Отражение кадра камеры (NV12, как отдаёт RTCCameraVideoCapturer) через vImage. Буферы берутся из своего пула:
/// новый на каждый кадр не выделяется. Другой формат — nil, кадр уйдёт без отражения.
final class PixelBufferMirror {
    private var pool: CVPixelBufferPool?
    private var poolKey: (width: Int, height: Int, format: OSType)?

    func mirrored(_ source: CVPixelBuffer, vertically: Bool) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(source)
        guard
            format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange || format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            let output = makeBuffer(width: CVPixelBufferGetWidth(source), height: CVPixelBufferGetHeight(source), format: format)
        else { return nil }

        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(output, [])
        defer {
            CVPixelBufferUnlockBaseAddress(output, [])
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
        }
        // Плоскость 0 — яркость (байт на точку), 1 — цвет парами Cb,Cr: пара отражается как одно 16-битное значение.
        for plane in 0..<2 {
            guard
                let sourceData = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                let outputData = CVPixelBufferGetBaseAddressOfPlane(output, plane)
            else { return nil }
            let height = vImagePixelCount(CVPixelBufferGetHeightOfPlane(source, plane))
            let width = vImagePixelCount(CVPixelBufferGetWidthOfPlane(source, plane))
            var from = vImage_Buffer(data: sourceData, height: height, width: width, rowBytes: CVPixelBufferGetBytesPerRowOfPlane(source, plane))
            var to = vImage_Buffer(data: outputData, height: height, width: width, rowBytes: CVPixelBufferGetBytesPerRowOfPlane(output, plane))
            let flags = vImage_Flags(kvImageNoFlags)
            let error = switch (plane, vertically) {
            case (0, false): vImageHorizontalReflect_Planar8(&from, &to, flags)
            case (0, true): vImageVerticalReflect_Planar8(&from, &to, flags)
            case (_, false): vImageHorizontalReflect_Planar16U(&from, &to, flags)
            case (_, true): vImageVerticalReflect_Planar16U(&from, &to, flags)
            }
            guard error == kvImageNoError else { return nil }
        }
        // Цветовое пространство и прочие метки кадра — как у исходного, иначе кодер может исказить цвета.
        CVBufferPropagateAttachments(source, output)
        return output
    }

    private func makeBuffer(width: Int, height: Int, format: OSType) -> CVPixelBuffer? {
        if poolKey?.width != width || poolKey?.height != height || poolKey?.format != format {
            let attributes: [CFString: Any] = [
                kCVPixelBufferPixelFormatTypeKey: format,
                kCVPixelBufferWidthKey: width,
                kCVPixelBufferHeightKey: height,
                // IOSurface — чтобы аппаратный кодер взял буфер без копирования.
                kCVPixelBufferIOSurfacePropertiesKey: [String: Any](),
            ]
            pool = nil
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
            poolKey = (width, height, format)
        }
        guard let pool else { return nil }
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        return buffer
    }
}
