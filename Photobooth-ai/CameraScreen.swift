import SwiftUI
import AVFoundation
import PhotosUI

struct CameraScreen: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var controller = CameraController()
    @State private var countdown: Int? = nil
    @State private var flashing: Bool = false
    @State private var capturing: Bool = false
    @State private var permissionDenied: Bool = false
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var showConsentSheet: Bool = false
    @State private var consentResolved: Bool = false
    @State private var helpPresented: Bool = false
    @State private var lastInteractionAt: Date = .now
    @State private var showIdleReminder: Bool = false
    @State private var idleTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live camera preview
            CameraPreviewView(controller: controller)
                .ignoresSafeArea()
                .scaleEffect(x: controller.isFront ? -1 : 1, y: 1, anchor: .center)

            // Permission denied fallback
            if permissionDenied {
                permissionDeniedOverlay
            }

            // Flash overlay on capture
            if flashing {
                Color.white.opacity(0.9)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            // Countdown overlay
            if let countdown {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    Text("\(countdown)")
                        .font(.system(size: 220, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 20)
                        .transition(.scale.combined(with: .opacity))
                        .id(countdown)
                }
            }

            // Top + bottom chrome
            VStack(spacing: 0) {
                topBar
                if app.settings(for: eventId).virtualAttendant.enabled {
                    let va = app.settings(for: eventId).virtualAttendant
                    VirtualAttendantPreview(greeting: va.greetingMessage, prompt: va.voicePromptText)
                        .padding(.top, 8)
                }
                Spacer()
                if showIdleReminder {
                    IdleReminderBanner()
                        .padding(.bottom, 8)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                bottomBar
            }
        }
        .task {
            // Show consent first if required; only prepareCamera once resolved.
            let disclaimer = app.settings(for: eventId).disclaimer
            if disclaimer.enabled && disclaimer.requireConsentBeforeCapture && !consentResolved {
                showConsentSheet = true
            } else {
                consentResolved = true
                await prepareCamera()
                startIdleWatch()
            }
        }
        .onDisappear {
            controller.stop()
            idleTask?.cancel()
            AttendantSpeech.shared.stop()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            bumpInteraction()
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    proceedWith(imageData: data)
                }
                pickerItem = nil
            }
        }
        .sheet(isPresented: $showConsentSheet, onDismiss: {
            // If the sheet dismissed without resolving, treat as decline.
            if !consentResolved { app.pop() }
        }) {
            DisclaimerConsentSheet(
                settings: app.settings(for: eventId).disclaimer,
                onAccept: {
                    consentResolved = true
                    app.recordConsent(for: eventId)
                    showConsentSheet = false
                    Task {
                        await prepareCamera()
                        startIdleWatch()
                    }
                },
                onDecline: {
                    consentResolved = false
                    showConsentSheet = false
                    app.pop()
                }
            )
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $helpPresented) {
            VirtualAttendantHelpSheet(settings: app.settings(for: eventId).virtualAttendant)
                .presentationDetents([.large])
        }
    }

    // MARK: - Idle watch

    private func bumpInteraction() {
        lastInteractionAt = .now
        if showIdleReminder { withAnimation { showIdleReminder = false } }
    }

    private func startIdleWatch() {
        idleTask?.cancel()
        let attendant = app.settings(for: eventId).virtualAttendant
        guard attendant.enabled, attendant.idleReminderEnabled, attendant.idleReminderSeconds > 0 else { return }
        let threshold = TimeInterval(attendant.idleReminderSeconds)
        idleTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                if Date().timeIntervalSince(lastInteractionAt) >= threshold, !showIdleReminder, countdown == nil, !capturing {
                    Haptics.tap(.light)
                    withAnimation { showIdleReminder = true }
                }
            }
        }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack(spacing: 10) {
            // Back arrow — pops one level off the navigation stack. The expected
            // flow is EventHub → push(.camera) → CameraScreen, so a single pop
            // lands operators back on their session control center without ever
            // creating duplicate EventHub screens or skipping to Mode Selection.
            Button {
                Haptics.tap()
                controller.stop()
                app.pop()
            } label: {
                glassCircleIcon("chevron.left")
            }
            .accessibilityLabel("Back to event")

            if app.settings(for: eventId).virtualAttendant.enabled,
               app.settings(for: eventId).virtualAttendant.helpButtonEnabled {
                Button {
                    Haptics.tap()
                    bumpInteraction()
                    helpPresented = true
                } label: {
                    glassCircleIcon("questionmark")
                }
                .accessibilityLabel("Help")
            }

            Spacer()
            Text(app.event(id: eventId)?.name ?? "Photobooth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            Spacer()
            Button {
                Haptics.tap()
                bumpInteraction()
                app.push(.settingsHub(eventId: eventId))
            } label: {
                glassCircleIcon("gearshape.fill")
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    /// Reusable circular glass top-bar icon.
    @ViewBuilder
    private func glassCircleIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.4))
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
    }

    private var bottomBar: some View {
        VStack(spacing: 16) {
            Text("Tap to capture — 3-second countdown")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4))
                .clipShape(Capsule())

            HStack(spacing: 28) {
                // Import from library
                PhotosPicker(selection: $pickerItem, matching: .images, preferredItemEncoding: .compatible) {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3.weight(.semibold))
                        Text("Import")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.4))
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    .clipShape(Circle())
                }
                .disabled(capturing || countdown != nil)
                .accessibilityLabel("Import photo from library")

                // Shutter
                Button {
                    startCountdown()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(.white, lineWidth: 4)
                            .frame(width: 86, height: 86)
                        Circle()
                            .fill(.white)
                            .frame(width: 72, height: 72)
                            .scaleEffect(capturing ? 0.9 : 1)
                    }
                }
                .disabled(capturing || countdown != nil || permissionDenied)
                .opacity(permissionDenied ? 0.4 : 1)
                .accessibilityLabel("Take photo")
                .accessibilityHint("Starts 3-second countdown, then captures")

                // Flip camera — moved from top-bar so settings can live there.
                Button {
                    Haptics.selection()
                    bumpInteraction()
                    Task { await controller.flip() }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .font(.title3.weight(.semibold))
                        Text("Flip")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(.black.opacity(0.4))
                    .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
                    .clipShape(Circle())
                }
                .disabled(capturing || countdown != nil || permissionDenied)
                .accessibilityLabel("Flip camera")
            }
        }
        .padding(.bottom, 36)
    }

    private var permissionDeniedOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "camera.metering.unknown")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(BoothifyTheme.violet)
                    .accessibilityHidden(true)
                Text("Camera permission needed")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Enable Camera access in Settings to use the photobooth. You can still import an existing photo from your library.")
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)

                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(maxWidth: 220)
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Actions

    private func prepareCamera() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            await controller.start()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            if granted {
                await controller.start()
            } else {
                permissionDenied = true
            }
        default:
            permissionDenied = true
        }
    }

    private func startCountdown() {
        guard countdown == nil, !capturing else { return }
        bumpInteraction()
        Haptics.tap(.medium)
        countdown = 3
        Task {
            for value in stride(from: 3, through: 1, by: -1) {
                withAnimation(.easeOut(duration: 0.2)) { countdown = value }
                Haptics.tap(.light)
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation { countdown = nil }
            await capture()
        }
    }

    private func capture() async {
        capturing = true
        Haptics.notify(.success)
        withAnimation(.easeIn(duration: 0.05)) { flashing = true }
        try? await Task.sleep(for: .milliseconds(120))
        withAnimation(.easeOut(duration: 0.25)) { flashing = false }

        do {
            // Guard FIRST — if there's no active video connection (Simulator with
            // no camera, or a real device where setup failed), throw a normal
            // Swift error before AVCapturePhotoOutput throws an uncatchable ObjC
            // exception ("No active and enabled video connection").
            guard controller.canCapturePhoto else {
                throw NSError(
                    domain: "Boothify",
                    code: -10,
                    userInfo: [NSLocalizedDescriptionKey: "No active camera connection"]
                )
            }
            let image = try await controller.capturePhoto()
            if let data = image.jpegData(compressionQuality: 0.85) {
                proceedWith(imageData: data)
            }
        } catch {
            // Fall back to a placeholder colored image so the demo flow still
            // moves (Simulator path).
            if let data = placeholderImageData() {
                proceedWith(imageData: data)
            }
        }
        capturing = false
    }

    private func proceedWith(imageData: Data) {
        controller.stop()
        app.push(.stylePicker(eventId: eventId, capturedImageData: imageData))
    }

    private func placeholderImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let img = renderer.image { ctx in
            UIColor(BoothifyTheme.violet).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        return img.jpegData(compressionQuality: 0.85)
    }
}

// MARK: - AVFoundation glue

@MainActor
@Observable
final class CameraController {
    let session = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private(set) var isFront: Bool = true
    private var currentInput: AVCaptureDeviceInput?
    private var captureContinuation: CheckedContinuation<UIImage, Error>?
    private let delegate = PhotoCaptureDelegate()

    /// True when the capture session has everything required to safely call
    /// `AVCapturePhotoOutput.capturePhoto`. On the Simulator there's no camera
    /// hardware so the connection won't be active — callers should fall back to
    /// the placeholder demo image when this returns false.
    var canCapturePhoto: Bool {
        guard session.isRunning else { return false }
        guard !session.inputs.isEmpty else { return false }
        guard session.outputs.contains(photoOutput) else { return false }
        guard let connection = photoOutput.connection(with: .video) else { return false }
        return connection.isEnabled && connection.isActive
    }

    func start() async {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Wire up output once.
        if !session.outputs.contains(photoOutput) {
            if session.canAddOutput(photoOutput) {
                session.addOutput(photoOutput)
            }
        }

        await reconfigureInput()

        session.commitConfiguration()

        // If the Simulator (or a permission-denied device) couldn't attach any
        // input, leave the session stopped. The UI stays usable; `capturePhoto`
        // will report "no active connection" instead of crashing.
        guard !session.inputs.isEmpty, session.outputs.contains(photoOutput) else { return }

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
        if isFront {
            // Mirror the captured image to match the on-screen preview.
            if let conn = photoOutput.connection(with: .video) {
                if conn.isVideoMirroringSupported {
                    conn.automaticallyAdjustsVideoMirroring = false
                    conn.isVideoMirrored = true
                }
            }
        }
        return try await withCheckedThrowingContinuation { cont in
            delegate.completion = { result in
                switch result {
                case .success(let image): cont.resume(returning: image)
                case .failure(let err):   cont.resume(throwing: err)
                }
            }
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
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
