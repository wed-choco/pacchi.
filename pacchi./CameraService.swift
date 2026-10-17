import Foundation
import Observation
import CoreGraphics
@preconcurrency import AVFoundation
import CoreImage
import ImageIO

@MainActor @Observable
final class CameraService {
    enum Status: Equatable { case idle, requesting, running, capturing, unavailable(String) }
    private(set) var status: Status = .idle
    private(set) var preview: CGImage?
    private(set) var captured: CapturedPhoto?
    private(set) var zoom = 1.0
    private(set) var maximumZoom = 1.0
    var filter: RetroPhotoFilter = .original { didSet { updateOptions() } }
    var dateStamp = false { didSet { updateOptions() } }
    private var generation = 0
    private var completion: (@MainActor () -> Void)?
    #if os(iOS) && !targetEnvironment(simulator)
    private let worker = CameraWorker()
    #endif
    var isCapturing: Bool { status == .capturing }
    func start() {
        guard status != .running, status != .requesting, status != .capturing else { return }
        generation += 1; let id = generation
        captured = nil; preview = nil
        #if targetEnvironment(simulator)
        status = .unavailable("Simulatorではカメラを使えません。iPhone実機で撮影してね。アルバムは実機と同じように使えます。")
        #elseif os(iOS)
        status = .requesting
        Task { @MainActor [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, self.generation == id else { return }
            guard allowed else { self.status = .unavailable("カメラが許可されていません。iPhoneの設定 → Pacchi. → カメラを確認してね。"); return }
            self.worker.start(filter: self.filter, stamp: self.dateStamp) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == id else { return }
                    switch event {
                    case .running(let maxZoom): self.maximumZoom = maxZoom; self.status = .running
                    case .preview(let image): self.preview = image
                    case .photo(let photo):
                        self.captured = photo; self.status = .running
                        let callback = self.completion; self.completion = nil; callback?()
                    case .captureError(let message): self.status = .running; self.completion = nil; self.errorMessage = message
                    case .unavailable(let message): self.status = .unavailable(message); self.completion = nil
                    }
                }
            }
        }
        #else
        status = .unavailable("撮影はiPhone実機で使えます。保存済みのアルバムはこの環境でも見られます。")
        #endif
    }
    var errorMessage: String?
    func capture(completion: @escaping @MainActor () -> Void) {
        guard status == .running else { return }
        errorMessage = nil; status = .capturing; self.completion = completion
        #if os(iOS) && !targetEnvironment(simulator)
        worker.capture()
        #else
        self.completion = nil; status = .unavailable("撮影にはiPhone実機が必要です。")
        #endif
    }
    func adjustZoom(_ delta: Double) {
        guard status == .running else { return }
        zoom = max(1, min(maximumZoom, zoom + delta))
        #if os(iOS) && !targetEnvironment(simulator)
        worker.setZoom(zoom)
        #endif
    }
    func stop() {
        generation += 1; completion = nil; preview = nil; status = .idle; zoom = 1; errorMessage = nil
        #if os(iOS) && !targetEnvironment(simulator)
        worker.stop()
        #endif
    }
    func discardCapture() { captured = nil }
    private func updateOptions() {
        guard !isCapturing else { return }
        #if os(iOS) && !targetEnvironment(simulator)
        worker.options(filter: filter, stamp: dateStamp)
        #endif
    }
}

#if os(iOS) && !targetEnvironment(simulator)
// All session, device, delegate, filter and observer state is confined to this serial queue.
nonisolated private final class CameraWorker: NSObject, @unchecked Sendable, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    enum Event: @unchecked Sendable {
        case running(Double), preview(CGImage), photo(CapturedPhoto), captureError(String), unavailable(String)
    }
    private let queue = DispatchQueue(label: "pacchi.camera.capture", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var device: AVCaptureDevice?
    private var configured = false
    private var active = false
    private var capturing = false
    private var captureID: Int64?
    private var lastFrame = 0.0
    private var filter: RetroPhotoFilter = .original
    private var stamp = false
    private var shotOptions: (RetroPhotoFilter, Bool, Date, String)?
    private var sink: (@Sendable (Event) -> Void)?
    private var observers: [NSObjectProtocol] = []
    func start(filter: RetroPhotoFilter, stamp: Bool, sink: @escaping @Sendable (Event) -> Void) {
        queue.async { [self] in
            self.filter = filter; self.stamp = stamp; self.sink = sink; active = true
            do {
                if !configured { try configure() }
                video.setSampleBufferDelegate(self, queue: queue)
                if !session.isRunning { session.startRunning() }
                guard session.isRunning else { throw PhotoError.unavailable }
                sink(.running(min(4, Double(device?.maxAvailableVideoZoomFactor ?? 1))))
            } catch { active = false; sink(.unavailable("カメラを開始できません。他のアプリを閉じて、もう一度お試しください。")) }
        }
    }
    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw PhotoError.unavailable }
        let input = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(output), session.canAddOutput(video) else { throw PhotoError.unavailable }
        session.addInput(input); session.addOutput(output); session.addOutput(video)
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.setSampleBufferDelegate(self, queue: queue)
        // The virtual candybar phone captures in portrait; preview and photo use the same orientation.
        for connection in [video.connection(with: .video), output.connection(with: .video)].compactMap({ $0 }) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
        device = camera; configured = true
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.queue.async { [weak self] in
                    guard let self, self.active else { return }
                    self.active = false; self.capturing = false
                    if self.session.isRunning { self.session.stopRunning() }
                    self.sink?(.unavailable("カメラが中断されました。OKで再開できます。"))
                }
            })
        }
    }
    func options(filter: RetroPhotoFilter, stamp: Bool) { queue.async { [self] in self.filter = filter; self.stamp = stamp } }
    func setZoom(_ zoom: Double) {
        queue.async { [self] in
            guard active, let device else { return }
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                device.videoZoomFactor = max(1, min(CGFloat(zoom), min(4, device.maxAvailableVideoZoomFactor)))
            } catch { sink?(.captureError("ズームを変更できませんでした。")) }
        }
    }
    func capture() {
        queue.async { [self] in
            guard active, session.isRunning, !capturing else { return }
            capturing = true
            shotOptions = (filter, stamp, Date(), TimeZone.current.identifier)
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            captureID = settings.uniqueID
            if output.isShutterSoundSuppressionSupported { settings.isShutterSoundSuppressionEnabled = true }
            settings.flashMode = .off
            settings.photoQualityPrioritization = .balanced
            output.capturePhoto(with: settings, delegate: self)
            let id = settings.uniqueID
            queue.asyncAfter(deadline: .now() + 15) { [weak self] in
                guard let self, self.active, self.captureID == id, self.capturing else { return }
                self.capturing = false; self.captureID = nil; self.shotOptions = nil
                self.sink?(.captureError("撮影がタイムアウトしました。もう一度お試しください。"))
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard active, !capturing, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.12 else { return }; lastFrame = now
        autoreleasepool {
            let source = CIImage(cvPixelBuffer: buffer)
            let factor = min(1, 320 / max(source.extent.width, source.extent.height))
            let small = source.transformed(by: CGAffineTransform(scaleX: factor, y: factor))
            if let image = try? PhotoProcessing.render(small, filter: filter, stamp: stamp, date: Date(), timeZone: TimeZone.current.identifier, context: context) {
                sink?(.preview(image))
            }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // AVFoundation does not promise this delegate runs on our session queue.
        let data = error == nil ? photo.fileDataRepresentation() : nil
        let id = photo.resolvedSettings.uniqueID
        queue.async { [self] in
            guard active, capturing, captureID == id else { return }
            defer { capturing = false; captureID = nil; shotOptions = nil }
            guard let data, let (filter, stamp, date, timeZone) = shotOptions else { sink?(.captureError("撮影できませんでした。もう一度お試しください。")); return }
            do {
                let original = try PhotoProcessing.normalized(data)
                let processed = try PhotoProcessing.render(CIImage(cgImage: original), filter: filter, stamp: stamp, date: date, timeZone: timeZone, context: context)
                let shot = CapturedPhoto(original: original, processed: processed,
                    originalJPEG: try PhotoProcessing.jpeg(original), processedJPEG: try PhotoProcessing.jpeg(processed),
                    capturedAt: date, filter: filter, dateStamp: stamp, timeZoneIdentifier: timeZone)
                sink?(.photo(shot))
            } catch { sink?(.captureError("写真を処理できませんでした。撮り直してね。")) }
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard error != nil else { return }
        let id = resolvedSettings.uniqueID
        queue.async { [self] in
            guard active, captureID == id else { return }
            capturing = false; captureID = nil; shotOptions = nil
            sink?(.captureError("撮影を完了できませんでした。もう一度お試しください。"))
        }
    }
    func stop() {
        queue.async { [self] in
            active = false; capturing = false; captureID = nil; shotOptions = nil; sink = nil
            video.setSampleBufferDelegate(nil, queue: nil)
            if session.isRunning { session.stopRunning() }
            if let device {
                do { try device.lockForConfiguration(); device.videoZoomFactor = 1; device.unlockForConfiguration() } catch {}
            }
        }
    }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        let session = session
        queue.async { if session.isRunning { session.stopRunning() } }
    }
}
#endif
