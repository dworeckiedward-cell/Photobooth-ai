import SwiftUI
import AVFoundation


@MainActor
@Observable
final class CameraController {
    /// Two operating modes. `.photo` keeps the original AI Photobooth flow
    /// (still images via `AVCapturePhotoOutput`). `.video` reconfigures the
    /// session for the 360 booth (`AVCaptureMovieFileOutput` + audio input +
    /// hardware stabilization). Switch at runtime by calling `start(mode:)` —
    /// the session is rebuilt safely.
    enum Mode { case photo, video }

    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var audioInput: AVCaptureDeviceInput?
    private(set) var currentMode: Mode = .photo
    private(set) var isRecording: Bool = false
    private(set) var isFront: Bool = true
    /// Operator setting (event.camera.mirrorSelfie). When false, the front camera
    /// is NOT mirrored — preview and captured output match the real-world view.
    var mirrorFrontCamera: Bool = true
    /// True when the front camera should be mirrored right now.
    var shouldMirror: Bool { isFront && mirrorFrontCamera }
    /// Operator setting (event.camera.stabilizationEnabled). Drives video
    /// stabilization for 360 / slow-mo recording.
    var stabilizationEnabled: Bool = true
    private var currentInput: AVCaptureDeviceInput?
    private let photoDelegate = PhotoCaptureDelegate()
    private let movieDelegate = MovieCaptureDelegate()

    /// True when the capture session has everything required to safely call
    /// `AVCapturePhotoOutput.capturePhoto`. On the Simulator there's no camera
    /// hardware so the connection won't be active — callers should fall back to
    /// the placeholder demo image when this returns false.
    var canCapturePhoto: Bool {
        guard currentMode == .photo else { return false }
        guard session.isRunning else { return false }
        guard !session.inputs.isEmpty else { return false }
        guard session.outputs.contains(photoOutput) else { return false }
        guard let connection = photoOutput.connection(with: .video) else { return false }
        return connection.isEnabled && connection.isActive
    }

    /// True when the current camera device supports 240fps capture (A9+ chips,
    /// iPhone 6s and later). Returns false on Simulator — slow-mo UI is hidden/
    /// grayed on unsupported devices.
    var supportsSlowMotion: Bool {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return false }
        return device.formats.contains { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 240 }
        }
    }

    /// True when video recording can actually start. Simulator and
    /// permission-denied devices return false; callers should surface a friendly
    /// message instead of crashing.
    var canRecordVideo: Bool {
        guard currentMode == .video else { return false }
        guard session.isRunning else { return false }
        guard session.outputs.contains(movieOutput) else { return false }
        guard let connection = movieOutput.connection(with: .video) else { return false }
        return connection.isEnabled && connection.isActive
    }

    func start(mode: Mode = .photo) async {
        currentMode = mode
        session.beginConfiguration()

        // Session preset — `.hd1920x1080` is the sweet spot for 360 booth and is
        // supported by every device we'd realistically run on. `.photo` keeps the
        // original AI Photobooth output quality intact.
        switch mode {
        case .photo:
            session.sessionPreset = .photo
            if session.outputs.contains(movieOutput) { session.removeOutput(movieOutput) }
            if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
        case .video:
            if session.canSetSessionPreset(.hd1920x1080) {
                session.sessionPreset = .hd1920x1080
            } else {
                session.sessionPreset = .high
            }
            if session.outputs.contains(photoOutput) { session.removeOutput(photoOutput) }
            if !session.outputs.contains(movieOutput), session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
        }

        await reconfigureInput()
        await reconfigureAudio(for: mode)

        session.commitConfiguration()

        if mode == .video {
            // M1: native AVFoundation stabilization. Applied AFTER commit because
            // the video connection only exists once the movie output is wired.
            configureStabilization()
        }

        // If the Simulator (or a permission-denied device) couldn't attach any
        // input, leave the session stopped. The UI stays usable; capture / record
        // calls will report "no active connection" instead of crashing.
        guard !session.inputs.isEmpty, !session.outputs.isEmpty else { return }

        // Starting the session blocks; do it off the main actor.
        let session = self.session
        await Task.detached {
            if !session.isRunning {
                session.startRunning()
            }
        }.value
    }

    func stop() {
        let session = self.session
        Task.detached {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    func flip() async {
        isFront.toggle()
        session.beginConfiguration()
        await reconfigureInput()
        session.commitConfiguration()
        if currentMode == .video {
            configureStabilization()
        }
    }

    private func reconfigureInput() async {
        if let currentInput {
            session.removeInput(currentInput)
            self.currentInput = nil
        }
        let position: AVCaptureDevice.Position = isFront ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) ??
                            AVCaptureDevice.default(for: .video) else {
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
            currentInput = input
        }
    }

    private func reconfigureAudio(for mode: Mode) async {
        // Tear down whatever was there. We add audio only in video mode so the
        // photo flow doesn't surface a microphone permission prompt unnecessarily.
        if let audioInput {
            session.removeInput(audioInput)
            self.audioInput = nil
        }
        guard mode == .video else { return }
        guard let device = AVCaptureDevice.default(for: .audio) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
            audioInput = input
        }
    }

    /// M1: enable native hardware stabilization on the movie output's video
    /// connection. AVFoundation silently falls back to the closest supported
    /// mode for the device, so we just request the strongest one we want.
    /// `.cinematicExtended` (iOS 13+, A12+) is the right mode for a static
    /// 360° pan — it smooths platform vibration without altering pacing.
    /// Phase 3 (blueprint 7.1): pick the best supported frame rate for the
    /// 360 quality path. Pure so the fallback policy is unit-testable:
    /// smallest supported rate ≥ target wins (least bandwidth for the goal);
    /// none ≥ target → highest available (honest fallback, caller logs).
    nonisolated static func bestFrameRate(supportedMaxRates: [Double], target: Double) -> Double? {
        let eligible = supportedMaxRates.filter { $0 >= target }
        if let best = eligible.min() { return best }
        return supportedMaxRates.max()
    }

    /// Configure the active device for high-fps video capture (default 120).
    /// Falls back to the highest available rate — NEVER silently pretends the
    /// target was hit; returns the rate actually configured.
    @discardableResult
    func configureHighFrameRate(target: Double = 120) async -> Double? {
        guard currentMode == .video,
              let input = session.inputs.first as? AVCaptureDeviceInput else { return nil }
        let device = input.device

        // Candidate formats: support ≥1080p and expose their max frame rate.
        struct Candidate { let format: AVCaptureDevice.Format; let maxRate: Double }
        let candidates: [Candidate] = device.formats.compactMap { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dims.width >= 1920, dims.height >= 1080 else { return nil }
            guard let maxRate = format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() else { return nil }
            return Candidate(format: format, maxRate: maxRate)
        }
        guard !candidates.isEmpty else { return nil }

        guard let chosenRate = Self.bestFrameRate(
            supportedMaxRates: candidates.map(\.maxRate), target: target
        ) else { return nil }
        // Among formats reaching the chosen rate, prefer the smallest ≥1080p
        // (memory discipline — no 4K buffers for a 1080-output pipeline).
        let format = candidates
            .filter { $0.maxRate >= chosenRate }
            .min { a, b in
                let da = CMVideoFormatDescriptionGetDimensions(a.format.formatDescription)
                let db = CMVideoFormatDescriptionGetDimensions(b.format.formatDescription)
                return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
            }!.format

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            let duration = CMTime(value: 1, timescale: CMTimeScale(chosenRate))
            device.activeVideoMinFrameDuration = duration
            device.activeVideoMaxFrameDuration = duration
            device.unlockForConfiguration()
        } catch {
            return nil
        }
        // Format switch resets the connection preferences.
        configureStabilization()
        return chosenRate
    }

    private func configureStabilization() {
        guard let connection = movieOutput.connection(with: .video),
              connection.isVideoStabilizationSupported else { return }

        guard stabilizationEnabled else {
            connection.preferredVideoStabilizationMode = .off
            return
        }

        // Pick the STRONGEST mode the active format actually supports, rather than
        // blindly requesting cinematicExtended (unsupported on older devices).
        // cinematic modes are face-aware and keep the subject stable as the rig
        // spins — exactly what a 360 / slow-mo booth needs.
        var preferred: [AVCaptureVideoStabilizationMode] = [
            .cinematicExtended, .cinematic, .standard, .auto,
        ]
        // iOS 18+: the strongest (Apple's newest) — prefer it when available.
        if #available(iOS 18.0, *) {
            preferred.insert(.cinematicExtendedEnhanced, at: 0)
        }
        if let format = currentInput?.device.activeFormat {
            connection.preferredVideoStabilizationMode =
                preferred.first { format.isVideoStabilizationModeSupported($0) } ?? .auto
        } else {
            connection.preferredVideoStabilizationMode = .auto
        }
    }

    /// Reconfigure the active camera device to record at 240fps (slow-motion).
    /// Must be called AFTER `start(mode: .video)` so the session is in video mode.
    /// Silently does nothing on devices/formats that don't support 240fps.
    func configureSlowMotion() async {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device else { return }

        // Find all formats that support 240fps, sorted by highest resolution first.
        let slowFormats = device.formats.filter { format in
            format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 240 }
        }.sorted { a, b in
            let dimA = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let dimB = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            return (Int(dimA.width) * Int(dimA.height)) > (Int(dimB.width) * Int(dimB.height))
        }
        guard let bestFormat = slowFormats.first else { return }

        session.beginConfiguration()
        do {
            try device.lockForConfiguration()
            device.activeFormat = bestFormat
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 240)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 240)
            device.unlockForConfiguration()
        } catch {
            // Couldn't lock — leave existing format; recording will still work
            // but may not be at 240fps.
        }
        session.commitConfiguration()

        // The 240fps format change can reset which stabilization modes the
        // connection supports — re-apply so slow-mo stays stabilized (LumaBooth
        // captures high-fps AND stabilizes together).
        configureStabilization()
    }

    /// Start recording to a new file under `<tmp or documents>/url`. Caller picks
    /// the destination so we can keep per-event organization in Booth360RecordingView.
    @discardableResult
    func startRecording(to url: URL) async throws -> URL {
        guard currentMode == .video else {
            throw NSError(domain: "Boothify", code: -20,
                          userInfo: [NSLocalizedDescriptionKey: "Camera is not in video mode"])
        }
        guard canRecordVideo else {
            throw NSError(domain: "Boothify", code: -21,
                          userInfo: [NSLocalizedDescriptionKey: "No active video connection"])
        }
        guard !movieOutput.isRecording else { return url }

        // Mirror front-camera output so the saved file matches what the operator
        // saw on the preview. AVCaptureMovieFileOutput won't mirror by default.
        if let connection = movieOutput.connection(with: .video), shouldMirror,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        // Clean up any stale file at the target URL so AVFoundation doesn't refuse to write.
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        movieOutput.startRecording(to: url, recordingDelegate: movieDelegate)
        isRecording = true
        return url
    }

    /// Stop the in-flight recording. Returns the on-disk URL of the finished
    /// `.mov`. Safe to call when not recording (returns immediately with an error).
    @discardableResult
    func stopRecording() async throws -> URL {
        guard isRecording, movieOutput.isRecording else {
            throw NSError(domain: "Boothify", code: -22,
                          userInfo: [NSLocalizedDescriptionKey: "Not recording"])
        }
        let url: URL = try await withCheckedThrowingContinuation { cont in
            movieDelegate.completion = { result in
                cont.resume(with: result)
            }
            movieOutput.stopRecording()
        }
        isRecording = false
        return url
    }

    /// Set speed-priority quality for burst capture (boomerang). Call with
    /// `false` after the burst to restore default quality.
    func setSpeedPriority(_ enabled: Bool) async {
        photoOutput.maxPhotoQualityPrioritization = enabled ? .speed : .balanced
    }

    func capturePhoto() async throws -> UIImage {
        // Defensive guard — `AVCapturePhotoOutput.capturePhoto(with:delegate:)`
        // throws an ObjC `NSInvalidArgumentException` (uncatchable from Swift's
        // do/catch) when there's no active+enabled video connection. Surface it
        // as a normal Swift error instead so the caller can show a placeholder.
        guard canCapturePhoto else {
            throw NSError(
                domain: "Boothify",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "No active camera connection"]
            )
        }

        let settings = AVCapturePhotoSettings()
        if shouldMirror {
            // Mirror the captured image to match the on-screen preview.
            if let conn = photoOutput.connection(with: .video) {
                if conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = false
                    conn.isVideoMirrored = true
                }
            }
        }
        return try await withCheckedThrowingContinuation { cont in
            photoDelegate.completion = { result in
                switch result {
                case .success(let image): cont.resume(returning: image)
                case .failure(let err):   cont.resume(throwing: err)
                }
            }
            photoOutput.capturePhoto(with: settings, delegate: photoDelegate)
        }
    }
}

// MARK: - Movie file output delegate

private final class MovieCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    var completion: ((Result<URL, Error>) -> Void)?

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        // AVCaptureFileOutput surfaces a non-nil error even on a clean stop —
        // when `AVErrorRecordingSuccessfullyFinishedKey` is true it means "user
        // stopped, file is fine". Treat that as success.
        if let error {
            let ns = error as NSError
            if let okFlag = ns.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool, okFlag {
                DispatchQueue.main.async { self.completion?(.success(outputFileURL)) }
                return
            }
            DispatchQueue.main.async { self.completion?(.failure(error)) }
            return
        }
        DispatchQueue.main.async { self.completion?(.success(outputFileURL)) }
    }
}

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var completion: ((Result<UIImage, Error>) -> Void)?

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            DispatchQueue.main.async { self.completion?(.failure(error)) }
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            DispatchQueue.main.async {
                self.completion?(.failure(NSError(domain: "Boothify", code: -1)))
            }
            return
        }
        DispatchQueue.main.async { self.completion?(.success(image)) }
    }
}

// MARK: - SwiftUI preview view

struct CameraPreviewView: UIViewRepresentable {
    let controller: CameraController

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = controller.session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.videoPreviewLayer.session = controller.session
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

// MARK: - Idle reminder banner

struct IdleReminderBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.wave.fill")
                .foregroundStyle(BoothifyTheme.amber)
            Text("Still there? Tap the shutter when you're ready.")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
    }
}
