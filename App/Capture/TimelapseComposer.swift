import AVFoundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import GrindCore

enum TimelapseComposer {
    struct Result {
        let videoURL: URL
        let thumbnailURL: URL?
        let duration: Double
    }

    enum ComposeError: Error { case noFrames, writerFailed }

    /// Turns the JPEG frames into an H.264 MP4 of about 45 seconds.
    static func compose(frames: [URL], output: URL, thumbnail: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        guard let first = frames.first, let firstImage = loadImage(first) else { throw ComposeError.noFrames }
        let width = firstImage.width & ~1
        let height = firstImage.height & ~1
        let fps = FrameSchedule.playbackFPS(frameCount: frames.count)

        try? FileManager.default.removeItem(at: output)
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 7_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw ComposeError.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ComposeError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        var written: Int64 = 0
        for (index, url) in frames.enumerated() {
            guard let image = index == 0 ? firstImage : loadImage(url) else { continue }
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 4_000_000)
            }
            guard let buffer = makeBuffer(from: image, pool: adaptor.pixelBufferPool, width: width, height: height) else { continue }
            if !adaptor.append(buffer, withPresentationTime: CMTime(value: written, timescale: CMTimeScale(fps))) {
                throw writer.error ?? ComposeError.writerFailed
            }
            written += 1
            if index % 15 == 0 { progress(Double(index) / Double(frames.count)) }
        }

        // Hold the last frame for half a second so the video doesn't cut off abruptly.
        let endTime = CMTime(value: written + Int64(fps / 2), timescale: CMTimeScale(fps))
        input.markAsFinished()
        writer.endSession(atSourceTime: endTime)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? ComposeError.writerFailed }
        progress(1)

        let thumbSource = frames[frames.count / 2]
        let thumbURL = writeThumbnail(from: thumbSource, to: thumbnail) ? thumbnail : nil
        return Result(videoURL: output, thumbnailURL: thumbURL, duration: endTime.seconds)
    }

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    private static func makeBuffer(from image: CGImage, pool: CVPixelBufferPool?, width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        if let pool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        } else {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        }
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func writeThumbnail(from url: URL, to destination: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, thumb, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
