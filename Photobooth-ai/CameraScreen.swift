import SwiftUI
import AVFoundation
import PhotosUI

// MARK: - Capture mode

enum ShutterMode: CaseIterable {
    case photo, boomerang, slowMo

    var label: String {
        switch self {
        case .photo:    return "Photo"
        case .boomerang: return "GIF"
        case .slowMo:   return "Slow-Mo"
        }
    }

    var icon: String {
        switch self {
        case .photo:    return "camera.fill"
        case .boomerang: return "repeat.circle.fill"
        case .slowMo:   return "gauge.with.needle"
        }
    }
}

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

    // Boomerang
    @State private var captureMode: ShutterMode = .photo
    @State private var boomerangProgress: Double = 0        // 0…1 while burst fires
    @State private var showShareSheet: Bool = false
    @State private var gifData: Data? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Slow-Mo
    @State private var slowMoRecording: Bool = false
    @State private var slowMoProgress: Double = 0           // 0…1 over 2 s recording
    @State private var slowMoShareURL: URL? = nil
    @State private var showSlowMoShare: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Live camera preview
            CameraPreviewView(controller: controller)
                .ignoresSafeArea()
                .scaleEffect(x: controller.shouldMirror ? -1 : 1, y: 1, anchor: .center)

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
                    // Dark vignette
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        center: .center,
                        startRadius: 80,
                        endRadius: 300
                    )
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                    VStack(spacing: 12) {
                        Text("\(countdown)")
                            .font(.system(size: 200, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: BoothifyTheme.violet.opacity(0.8), radius: 30, y: 0)
                            .shadow(color: .black.opacity(0.5), radius: 10)
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 1.4).combined(with: .opacity),
                                    removal: .scale(scale: 0.6).combined(with: .opacity)
                                )
                            )
                            .id(countdown)

                        Text(countdown == 1 ? "SMILE!" : "Get ready")
                            .font(.headline.weight(.bold))
                            .kerning(1.5)
                            .foregroundStyle(.white.opacity(0.85))
                            .textCase(.uppercase)
                            .transition(.opacity)
                            .id("label-\(countdown)")
                    }
                }
                .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.65), value: countdown)
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
        .onAppear { KioskManager.beginKeepAwake() }
        .onDisappear {
            KioskManager.endKeepAwake()
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
        .sheet(isPresented: $showShareSheet) {
            if let gifData {
                ShareSheet(items: [gifData])
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showSlowMoShare) {
            if let url = slowMoShareURL {
                ShareSheet(items: [url])
                    .ignoresSafeArea()
            }
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
            HStack(spacing: 8) {
                Text(app.event(id: eventId)?.name ?? "Photobooth")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                // 240fps badge — shown only in Slow-Mo mode
                if captureMode == .slowMo {
                    Text("240fps")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(BoothifyTheme.violet)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(BoothifyTheme.violet.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(BoothifyTheme.violet.opacity(0.5), lineWidth: 1))
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.4))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            .animation(reduceMotion ? nil : .spring(response: 0.3), value: captureMode)
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
            // Hint text — context-aware
            Group {
                switch captureMode {
                case .photo:
                    Text(Loc.t("Tap to capture", pl: "Dotknij, aby zrobić zdjęcie", de: "Tippen zum Aufnehmen"))
                case .boomerang:
                    Text("Tap to record GIF burst")
                case .slowMo:
                    if !controller.supportsSlowMotion {
                        Text("Requires iPhone with 240fps camera")
                            .foregroundStyle(BoothifyTheme.amber)
                    } else if slowMoRecording {
                        Text("Recording… tap to stop early")
                    } else {
                        Text("Tap to record 2s at 240fps — 8× slower playback")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.black.opacity(0.4))
            .clipShape(Capsule())
            .animation(reduceMotion ? nil : .default, value: captureMode)
            .animation(reduceMotion ? nil : .default, value: slowMoRecording)

            // Mode picker
            HStack(spacing: 0) {
                ForEach(ShutterMode.allCases, id: \.self) { mode in
                    // Hide slow-mo on unsupported devices (show grayed-out)
                    Button {
                        guard captureMode != mode else { return }
                        guard !(mode == .slowMo && !controller.supportsSlowMotion) else { return }
                        Haptics.selection()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3)) {
                            captureMode = mode
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: mode.icon)
                                .font(.caption.weight(.semibold))
                            Text(mode.label)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(captureMode == mode ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(captureMode == mode ? Color.white : Color.clear)
                        .clipShape(Capsule())
                    }
                    .opacity(mode == .slowMo && !controller.supportsSlowMotion ? 0.4 : 1)
                    .disabled(mode == .slowMo && !controller.supportsSlowMotion)
                    .accessibilityLabel("\(mode.label) mode")
                }
            }
            .padding(3)
            .background(.black.opacity(0.4))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))

            HStack(spacing: 28) {
                // Import from library (hidden in slow-mo recording)
                if !slowMoRecording {
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
                    .disabled(capturing || countdown != nil || captureMode == .slowMo)
                    .opacity(captureMode == .slowMo ? 0.4 : 1)
                    .accessibilityLabel("Import photo from library")
                    .transition(.opacity)
                } else {
                    // Placeholder to keep layout stable
                    Color.clear.frame(width: 64, height: 64)
                }

                // Primary action button
                switch captureMode {
                case .photo, .boomerang:
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
                    .accessibilityLabel(captureMode == .photo ? "Take photo" : "Record GIF")
                    .accessibilityHint(captureMode == .photo ? "Starts the countdown, then captures" : "Records a burst for GIF")

                case .slowMo:
                    slowMoButton
                }

                // Flip camera
                if !slowMoRecording {
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
                    .disabled(capturing || countdown != nil || permissionDenied || slowMoRecording)
                    .accessibilityLabel("Flip camera")
                    .transition(.opacity)
                } else {
                    Color.clear.frame(width: 64, height: 64)
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.35), value: slowMoRecording)
        }
        .padding(.bottom, 36)
    }

    // MARK: - Slow-Mo button

    @ViewBuilder
    private var slowMoButton: some View {
        let isDisabled = permissionDenied || !controller.supportsSlowMotion
        Button {
            if slowMoRecording {
                stopSlowMo()
            } else {
                startSlowMo()
            }
        } label: {
            ZStack {
                // Outer progress ring (violet, fills over 2 s)
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 5)
                    .frame(width: 86, height: 86)
                Circle()
                    .trim(from: 0, to: slowMoRecording ? slowMoProgress : 0)
                    .stroke(BoothifyTheme.violet, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .frame(width: 86, height: 86)
                    .rotationEffect(.degrees(-90))
                    .animation(slowMoRecording && !reduceMotion ? .linear(duration: 0.1) : nil, value: slowMoProgress)

                // Inner indicator: red square while recording, white circle at rest
                if slowMoRecording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 30, height: 30)
                        .opacity(reduceMotion ? 1 : 1)
                } else {
                    Circle()
                        .fill(BoothifyTheme.violet)
                        .frame(width: 72, height: 72)
                    Image(systemName: "gauge.with.needle")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
        .accessibilityLabel(slowMoRecording ? "Stop slow-motion recording" : "Start slow-motion recording")
        .accessibilityHint(slowMoRecording ? "Stops recording and prepares video" : "Records 2 seconds at 240fps, plays back 8× slower")
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
        // Honor the operator's mirror-selfie setting (was previously ignored — the
        // front camera was always mirrored). Read live so it reflects the event.
        controller.mirrorFrontCamera = app.settings(for: eventId).camera.mirrorSelfie
        // Video stabilization (nil = on) for 360 / slow-mo recording.
        controller.stabilizationEnabled = app.settings(for: eventId).camera.stabilizationEnabled ?? true
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
        // Operator-configured countdown (was hardcoded to 3). 0 → snap immediately.
        let seconds = max(0, app.settings(for: eventId).capture.countdownFirstPhoto)
        guard seconds > 0 else {
            Task { await capture() }
            return
        }
        countdown = seconds
        Task {
            for value in stride(from: seconds, through: 1, by: -1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { countdown = value }
                let style: UIImpactFeedbackGenerator.FeedbackStyle = value == 1 ? .heavy : .medium
                Haptics.tap(style)
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation { countdown = nil }
            await capture()
        }
    }

    private func capture() async {
        switch captureMode {
        case .photo:
            await capturePhoto()
        case .boomerang:
            await captureBoomerang()
        case .slowMo:
            break  // handled by startSlowMo/stopSlowMo — capture() is never called for slowMo
        }
    }

    private func capturePhoto() async {
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
            let quality = app.settings(for: eventId).capture.quality
            if let data = image.jpegData(compressionQuality: quality) {
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

    private func captureBoomerang() async {
        capturing = true
        boomerangProgress = 0
        Haptics.tap(.medium)

        let frameCount = 20
        let interval: TimeInterval = 0.075

        var frames: [UIImage] = []

        if controller.canCapturePhoto {
            // Speed-priority burst via photo output
            await controller.setSpeedPriority(true)
            for i in 0..<frameCount {
                do {
                    let img = try await controller.capturePhoto()
                    frames.append(img)
                } catch {
                    // Skip failed frames — GIF may have fewer than 20 frames
                }
                Haptics.tap(.light)
                withAnimation { boomerangProgress = Double(i + 1) / Double(frameCount) }
                if i < frameCount - 1 {
                    try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
                }
            }
            await controller.setSpeedPriority(false)
        } else {
            // Simulator / no camera: generate colored placeholder frames
            for i in 0..<frameCount {
                let hue = Double(i) / Double(frameCount)
                let renderer = UIGraphicsImageRenderer(size: CGSize(width: 480, height: 480))
                let img = renderer.image { ctx in
                    UIColor(hue: hue, saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                    ctx.fill(CGRect(x: 0, y: 0, width: 480, height: 480))
                }
                frames.append(img)
                Haptics.tap(.light)
                withAnimation { boomerangProgress = Double(i + 1) / Double(frameCount) }
                try? await Task.sleep(for: .milliseconds(Int(interval * 1000)))
            }
        }

        // Encode GIF on background thread (CPU-bound)
        let encodedData = await Task.detached(priority: .userInitiated) {
            GIFEncoder.encode(frames: frames, boomerang: true)
        }.value

        if let data = encodedData {
            gifData = data
            Haptics.notify(.success)
            showShareSheet = true
        }

        boomerangProgress = 0
        capturing = false
    }

    private func proceedWith(imageData: Data) {
        let bg = app.settings(for: eventId).backgroundRemoval
        // No-AI booth: when the operator has no AI styles enabled, skip the AI
        // style picker entirely and go straight to on-device Instant Looks.
        let noAI = app.settings(for: eventId).aiPortraits.enabledStyles.isEmpty
        func next(_ data: Data) -> Route {
            noAI
                ? .instantLooks(eventId: eventId, capturedImageData: data)
                : .stylePicker(eventId: eventId, capturedImageData: data)
        }

        // Real green-screen / background replacement (Vision person segmentation),
        // applied on-device before the photo continues. Off → push immediately.
        guard bg.enabled, bg.mode != .off else {
            controller.stop()
            app.push(next(imageData))
            return
        }
        capturing = true
        Task.detached(priority: .userInitiated) {
            let processed = BackgroundReplacer.process(imageData, settings: bg)
            await MainActor.run {
                capturing = false
                controller.stop()
                app.push(next(processed))
            }
        }
    }

    private func placeholderImageData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1024, height: 1024))
        let img = renderer.image { ctx in
            UIColor(BoothifyTheme.violet).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
        }
        return img.jpegData(compressionQuality: 0.85)
    }

    // MARK: - Slow-Mo actions

    private func startSlowMo() {
        guard !slowMoRecording, !capturing else { return }
        bumpInteraction()
        slowMoProgress = 0
        Task {
            // Switch camera to video mode + configure 240fps
            await controller.start(mode: .video)
            await controller.configureSlowMotion()

            guard controller.canRecordVideo else { return }

            let tmpDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("SlowMo", isDirectory: true)
            let url = tmpDir.appendingPathComponent("slomo_\(Date().timeIntervalSince1970).mov")

            do {
                try await controller.startRecording(to: url)
            } catch {
                return
            }

            slowMoRecording = true
            Haptics.tap(.medium)

            // Drive progress ring over 2 seconds, auto-stop at end
            let duration: Double = 2.0
            let steps = 20
            for i in 1...steps {
                if !slowMoRecording { break }  // early stop by user
                try? await Task.sleep(for: .milliseconds(Int(duration / Double(steps) * 1000)))
                if !slowMoRecording { break }
                slowMoProgress = Double(i) / Double(steps)
            }

            // Auto-stop if still recording
            if slowMoRecording {
                stopSlowMo()
            }
        }
    }

    private func stopSlowMo() {
        guard slowMoRecording else { return }
        slowMoRecording = false
        Haptics.notify(.success)
        Task {
            do {
                let recordedURL = try await controller.stopRecording()
                // Copy to a stable Documents location for sharing
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let destDir = docs.appendingPathComponent("SlowMo", isDirectory: true)
                try? FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                let dest = destDir.appendingPathComponent("slomo_\(Date().timeIntervalSince1970).mov")
                try? FileManager.default.copyItem(at: recordedURL, to: dest)
                slowMoShareURL = FileManager.default.fileExists(atPath: dest.path) ? dest : recordedURL
                showSlowMoShare = true
            } catch {
                // Recording may have auto-stopped already; nothing to do
            }
            // Restore photo mode so normal shutter works
            slowMoProgress = 0
            await controller.start(mode: .photo)
        }
    }
}

// MARK: - AVFoundation glue

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
