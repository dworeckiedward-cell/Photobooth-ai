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
                    Text(Loc.t("Tap to record GIF burst", pl: "Dotknij, aby nagrać GIF", de: "Tippen für GIF-Aufnahme"))
                case .slowMo:
                    if !controller.supportsSlowMotion {
                        Text(Loc.t("Requires iPhone with 240fps camera", pl: "Wymaga iPhone'a z kamerą 240 kl./s", de: "Erfordert iPhone mit 240-fps-Kamera"))
                            .foregroundStyle(BoothifyTheme.amber)
                    } else if slowMoRecording {
                        Text(Loc.t("Recording… tap to stop early", pl: "Nagrywanie… dotknij, aby zatrzymać", de: "Aufnahme… zum Stoppen tippen"))
                    } else {
                        Text(Loc.t("Tap to record 2s at 240fps — 8× slower playback", pl: "Nagraj 2 s w 240 kl./s — 8× wolniejsze odtwarzanie", de: "2 s bei 240 fps — 8× langsamere Wiedergabe"))
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

