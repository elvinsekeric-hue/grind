import AVFoundation
import CoreImage
import UIKit
import GrindCore

/// Owns the camera. The same capture session drives the live preview in the
/// setup screen and the frame grabbing while a session runs, so starting is instant.
/// Frames are written as JPEGs to disk; that keeps memory flat and lets a crashed
/// session be turned into a video on the next launch.
final class TimelapseRecorder: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "grind.capture.session")
    private let frameQueue = DispatchQueue(label: "grind.capture.frames", qos: .utility)
    private let output = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

    private let lock = NSLock()
    private var capturing = false
    private var lastCapture: CFAbsoluteTime = 0
    private var schedule = FrameSchedule()
    private var framesDir: URL = Storage.framesDir

    private(set) var position: CameraPosition = .front
    private(set) var isConfigured = false

    /// Called on the main queue with the number of frames currently kept.
    var onFrameCount: (@MainActor (Int) -> Void)?

    static var isAuthorized: Bool { AVCaptureDevice.authorizationStatus(for: .video) == .authorized }
    static var isDenied: Bool {
        let s = AVCaptureDevice.authorizationStatus(for: .video)
        return s == .denied || s == .restricted
    }

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    // MARK: Session

    func configure(position: CameraPosition) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                self.configureOnQueue(position: position)
                done.resume()
            }
        }
    }

    private func configureOnQueue(position: CameraPosition) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }

        if let input { session.removeInput(input) }
        input = nil

        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let newInput = try? AVCaptureDeviceInput(device: device), session.canAddInput(newInput) else { return }
        session.addInput(newInput)
        input = newInput
        self.position = position

        if !session.outputs.contains(output) {
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.setSampleBufferDelegate(self, queue: frameQueue)
            if session.canAddOutput(output) { session.addOutput(output) }
        }

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = position == .front
            }
        }
        isConfigured = true
    }

    func startRunning() {
        sessionQueue.async {
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stopRunning() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    /// Lower the sensor frame rate while recording behind a black screen to save battery.
    func setFrameRate(_ fps: Double) {
        sessionQueue.async {
            guard let device = self.input?.device,
                  let range = device.activeFormat.videoSupportedFrameRateRanges.max(by: { $0.maxFrameRate < $1.maxFrameRate })
            else { return }
            let target = min(max(fps, range.minFrameRate), range.maxFrameRate)
            let duration = CMTime(seconds: 1 / target, preferredTimescale: 600)
            do {
                try device.lockForConfiguration()
                device.activeVideoMinFrameDuration = duration
                device.activeVideoMaxFrameDuration = duration
                device.unlockForConfiguration()
            } catch {}
        }
    }

    // MARK: Frame capture

    func resetFrames() {
        lock.lock()
        schedule = FrameSchedule()
        capturing = false
        lastCapture = 0
        lock.unlock()
        try? FileManager.default.removeItem(at: Storage.framesDir)
        framesDir = Storage.framesDir
    }

    func beginCapturing() {
        lock.lock()
        capturing = true
        lock.unlock()
    }

    func pauseCapturing() {
        lock.lock()
        capturing = false
        lock.unlock()
    }

    var keptFrameCount: Int {
        lock.lock(); defer { lock.unlock() }
        return schedule.kept.count
    }

    /// Wait until in-flight frame writes are done.
    func drain() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            frameQueue.async { done.resume() }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        guard capturing, schedule.shouldCapture(secondsSinceLast: now - lastCapture) else {
            lock.unlock()
            return
        }
        lastCapture = now
        let (id, dropped) = schedule.appendFrame()
        let count = schedule.kept.count
        let dir = framesDir
        lock.unlock()

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        let options = [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.62]
        if let data = ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) {
            try? data.write(to: dir.appendingPathComponent(Self.fileName(id)))
        }
        for old in dropped {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(Self.fileName(old)))
        }

        if let onFrameCount {
            DispatchQueue.main.async { MainActor.assumeIsolated { onFrameCount(count) } }
        }
    }

    static func fileName(_ id: Int) -> String { String(format: "%08d.jpg", id) }
}
