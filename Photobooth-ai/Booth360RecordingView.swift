import SwiftUI
import AVFoundation
import AudioToolbox
import UniformTypeIdentifiers

/// 360 AI Booth recording screen — full-screen camera preview with countdown,
/// fake-recording timer, and beep + haptic feedback. Frontend MVP: we don't
/// actually write a video file; on duration end we create a `Booth360Job` with
/// `rawVideoLocalURL = nil` and push to the Processing screen for the mock
/// pipeline.
struct Booth360RecordingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventId: UUID

    @State private var controller = CameraController()
    @State private var showConsentSheet: Bool = false
    @State private var consentResolved: Bool = false
    @State private var storageBlocked: Bool = false
    @State private var countdown: Int? = nil
    @State private var recording: Bool = false
    @State private var recordingElapsed: TimeInterval = 0
    @State private var recordingTask: Task<Void, Never>?
    @State private var permissionDenied: Bool = false
    @State private var permissionMessage: String? = nil
    @State private var activeRecordingURL: URL? = nil
    // M4 quick-controls state
    @State private var musicPickerPresented: Bool = false
    @State private var presetSheetPresented: Bool = false
    @State private var lastMusicError: String? = nil

    private var ai360: AI360Settings { app.settings(for: eventId).ai360 }
    private var brand: BrandOverlaySettings { app.settings(for: eventId).brandOverlay }
    private var duration: TimeInterval { max(2.0, ai360.recordingDurationSeconds) }
    private var countdownStart: Int { max(1, ai360.countdownSeconds) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            CameraPreviewView(controller: controller)
                .ignoresSafeArea()
                .scaleEffect(x: controller.isFront ? -1 : 1, y: 1, anchor: .center)

            // M1 safe-area overlay. `.cinematicExtended` stabilization crops ~10%
            // off each side, so the preview shows MORE than the final file. The
            // ramka tells the operator what will actually be captured.
            // Honest crop guide: only when the chosen preset actually crops
            // (Phase 6 philosophy — never show a crop that won't happen).
            if StabilizationPreset.effective(from: app.settings(for: eventId).camera) != .off {
                StabilizationSafeAreaFrame()
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }

            if permissionDenied {
                permissionOverlay
            }

            if let countdown {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    VStack(spacing: BoothifySpacing.sm) {
                        Text("\(countdown)")
                            .font(.system(size: 220, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.6), radius: 20)
                            .transition(.scale.combined(with: .opacity))
                            .id(countdown)
                        // Prepare -> NOW choreography for the guest on the platform.
                        Text(countdown == 1
                             ? Loc.t("GO!", pl: "START!", de: "LOS!")
                             : Loc.t("Get ready", pl: "Przygotuj się", de: "Mach dich bereit"))
                            .font(.title2.weight(.heavy))
                            .kerning(1.5)
                            .foregroundStyle(countdown == 1 ? BoothifyTheme.amber : .white.opacity(0.85))
                            .textCase(.uppercase)
                            .transition(.opacity)
                            .id("cue-\(countdown)")
                    }
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if recording {
                    instructionPill
                        .padding(.bottom, 14)
                }
                bottomBar
            }
        }
        .navigationBarHidden(true)
        .task { await prepareCamera() }
        .sheet(isPresented: $showConsentSheet, onDismiss: {
            if !consentResolved { app.pop() }   // decline/dismiss = leave
        }) {
            DisclaimerConsentSheet(
                settings: app.settings(for: eventId).disclaimer,
                onAccept: {
                    consentResolved = true
                    app.recordConsent(for: eventId)
                    showConsentSheet = false
                    Task { await prepareCamera() }
                },
                onDecline: {
                    consentResolved = false
                    showConsentSheet = false
                    app.pop()
                }
            )
            .interactiveDismissDisabled(true)
        }
        .alert("Not enough storage", isPresented: $storageBlocked) {
            Button("OK") { app.pop() }
        } message: {
            Text("Free up space on this device before recording — high-speed 360 captures are large.")
        }
        .onDisappear {
            controller.stop()
            recordingTask?.cancel()
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                recordingTask?.cancel()
                controller.stop()
                app.pop()
            } label: {
                glassCircle("chevron.left")
            }
            .disabled(recording)
            .opacity(recording ? 0.4 : 1)
            .accessibilityLabel("Back to event")

            Spacer()
            Text(app.event(id: eventId)?.name ?? "360 AI Booth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.black.opacity(0.4), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
            Spacer()
            // Operator control — hidden from guests in kiosk mode.
            if !app.isKiosk {
                Button {
                    Haptics.tap()
                    app.push(.settings360Hub(eventId: eventId))
                } label: {
                    glassCircle("gearshape.fill")
                }
                .disabled(recording)
                .opacity(recording ? 0.4 : 1)
                .accessibilityLabel("360 settings")
            } else {
                // Keep the title optically centered.
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    @ViewBuilder
    private func glassCircle(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(.black.opacity(0.4))
            .clipShape(Circle())
            .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Instruction + recording pill

    private var instructionPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "rotate.3d")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BoothifyTheme.amber)
            Text(Loc.t("Keep the pose — you're spinning!", pl: "Trzymaj pozę — kręcisz się!", de: "Pose halten — du drehst dich!"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        VStack(spacing: 16) {
            if recording {
                recordingStatus
            } else if countdown == nil {
                Text(Loc.t("Tap to start a \(Int(duration))s spin", pl: "Dotknij — start \(Int(duration))-sekundowego nagrania", de: "Tippen — \(Int(duration))-Sekunden-Aufnahme starten"))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
            }

            // M4: music ← REC → presets quick-controls row. Operator-only —
            // kiosk guests get a clean single-button stage.
            HStack(alignment: .center, spacing: BoothifySpacing.xl + BoothifySpacing.xs) {
                if !app.isKiosk { musicButton }
                recordButton
                if !app.isKiosk { presetButton }
            }
        }
        .padding(.bottom, 36)
        .fileImporter(
            isPresented: $musicPickerPresented,
            allowedContentTypes: [.audio, .mp3, .wav, .mpeg4Audio, UTType("public.mp3") ?? .audio],
            allowsMultipleSelection: false
        ) { result in
            handleMusicPick(result)
        }
        .sheet(isPresented: $presetSheetPresented) {
            QuickPresetsSheet(eventId: eventId)
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
    }

    private var hasSoundtrack: Bool {
        ai360.soundtrackRelativePath != nil
    }

    private var musicButton: some View {
        Button {
            Haptics.tap()
            musicPickerPresented = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: hasSoundtrack ? "music.note.list" : "music.note")
                    .font(.title3.weight(.semibold))
                Text(hasSoundtrack ? "Track" : "Music")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(hasSoundtrack ? BoothifyTheme.amber : .white)
            .frame(width: 64, height: 64)
            .background(.black.opacity(0.4))
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
            .clipShape(Circle())
        }
        .disabled(recording || countdown != nil)
        .opacity(recording || countdown != nil ? 0.4 : 1)
        .accessibilityLabel(hasSoundtrack ? "Change soundtrack" : "Choose soundtrack")
    }

    private var presetButton: some View {
        Button {
            Haptics.tap()
            presetSheetPresented = true
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.title3.weight(.semibold))
                Text("Presets")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.black.opacity(0.4))
            .overlay(Circle().stroke(.white.opacity(0.2), lineWidth: 1))
            .clipShape(Circle())
        }
        .disabled(recording || countdown != nil)
        .opacity(recording || countdown != nil ? 0.4 : 1)
        .accessibilityLabel("Quick presets — duration and quality")
    }

    private func handleMusicPick(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let src = urls.first else { return }
            do {
                // Security-scoped resource — required for files outside the app sandbox.
                let didStart = src.startAccessingSecurityScopedResource()
                defer { if didStart { src.stopAccessingSecurityScopedResource() } }

                let folder = Self.audioFolder(eventId: eventId)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent(src.lastPathComponent)
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(at: src, to: dest)

                var current = app.settings(for: eventId)
                current.ai360.soundtrackRelativePath = "audio/\(src.lastPathComponent)"
                current.ai360.soundtrackName = src.deletingPathExtension().lastPathComponent
                app.updateSettings(current, for: eventId)
                Haptics.notify(.success)
            } catch {
                lastMusicError = error.localizedDescription
                Haptics.notify(.error)
            }
        case .failure(let error):
            lastMusicError = error.localizedDescription
        }
    }

    private static func audioFolder(eventId: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
            .appendingPathComponent("audio", isDirectory: true)
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(BoothifyTheme.recording)
                .frame(width: 8, height: 8)
            Text("REC")
                .font(.caption2.weight(.bold))
                .kerning(1.0)
                .foregroundStyle(.white)
            Text(timeString)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(BoothifyTheme.recording.opacity(0.6), lineWidth: 1))
    }

    private var recordButton: some View {
        Button {
            beginCountdown()
        } label: {
            ZStack {
                // Progress ring (visible during recording)
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 5)
                    .frame(width: 92, height: 92)
                if recording {
                    Circle()
                        .trim(from: 0, to: min(1.0, recordingElapsed / duration))
                        .stroke(BoothifyTheme.amber, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 92, height: 92)
                        .animation(reduceMotion ? nil : .linear(duration: 0.1), value: recordingElapsed)
                }
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 86, height: 86)
                // Inner state
                if recording {
                    RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous)
                        .fill(BoothifyTheme.recording)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(BoothifyTheme.recording)
                        .frame(width: 70, height: 70)
                        .scaleEffect(countdown != nil ? 0.85 : 1)
                }
            }
        }
        .disabled(recording || countdown != nil || permissionDenied)
        .opacity(permissionDenied ? 0.4 : 1)
        .accessibilityLabel(recording ? "Recording — wait for end" : "Start 360 recording")
    }

    private var timeString: String {
        let remaining = max(0, duration - recordingElapsed)
        let secs = Int(ceil(remaining))
        return String(format: "00:%02d", secs)
    }

    // MARK: - Permission overlay

    private var permissionOverlay: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "video.slash")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundStyle(BoothifyTheme.amber)
                    .accessibilityHidden(true)
                Text("Camera permission needed")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(permissionMessage ?? "Enable Camera access in Settings to use the 360 booth.")
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
        // GDPR (blueprint §8): the consent gate now guards the 360 path too —
        // it used to live only on the removed photo CameraScreen.
        let disclaimer = app.settings(for: eventId).disclaimer
        if disclaimer.enabled && disclaimer.requireConsentBeforeCapture && !consentResolved {
            showConsentSheet = true
            return
        }
        // Need BOTH camera + microphone for video recording. We surface a single
        // permission overlay covering whichever one is missing.
        let cameraOK = await ensurePermission(for: .video)
        let micOK = await ensurePermission(for: .audio)

        guard cameraOK else {
            permissionDenied = true
            permissionMessage = "Enable Camera access in Settings to use the 360 booth."
            return
        }
        guard micOK else {
            permissionDenied = true
            permissionMessage = "Enable Microphone access in Settings so the 360 video can include audio."
            return
        }

        // Honor the operator's stabilization setting (nil = on) before the session
        // configures the recording connection. Smooths the spinning 360 footage.
        let cameraSettings = app.settings(for: eventId).camera
        controller.stabilizationEnabled = cameraSettings.stabilizationEnabled ?? true
        controller.stabilizationPreset = StabilizationPreset.effective(from: cameraSettings)
        await controller.start(mode: .video)
        // Blueprint 7.1: 120 fps quality path — logged fallback, never a
        // silent pretend. NEEDS-DEVICE for real verification.
        let achieved = await controller.configureHighFrameRate(target: 120)
        if let achieved, achieved < 120 {
            SentryClient.shared.breadcrumb(
                "high-fps fallback", category: "capture",
                data: ["achieved_fps": "\(Int(achieved))"]
            )
        }
    }

    /// Returns true when the user already granted (or now grants) access. False
    /// otherwise — caller surfaces the permission overlay.
    private func ensurePermission(for media: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: media) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: media)
        default: return false
        }
    }

    private func beginCountdown() {
        guard !recording, countdown == nil else { return }
        Haptics.tap(.medium)
        countdown = countdownStart
        Task {
            for value in stride(from: countdownStart, through: 1, by: -1) {
                withAnimation(reduceMotion ? nil : BoothifyMotion.quickTap) { countdown = value }   // RA5
                Haptics.tap(.light)
                // System beep — short audio cue per countdown tick
                AudioServicesPlaySystemSound(SystemSoundID(1306))
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation(reduceMotion ? nil : BoothifyMotion.quickTap) { countdown = nil }     // RA5
            startRecording()
        }
    }

    private func startRecording() {
        // Low storage → block with a clear message (blueprint 7.1 edge).
        guard !StorageLifecycle.shared.isStorageLow() else {
            storageBlocked = true
            return
        }
        recording = true
        recordingElapsed = 0
        Haptics.notify(.success)
        // Audible "start" cue
        AudioServicesPlaySystemSound(SystemSoundID(1057))
        // P4 — breadcrumb for the recording start. Helps correlate any
        // subsequent FFmpeg crash / upload failure with the take that
        // produced it. Duration is the planned length; actual elapsed
        // ships on finishRecording crumb.
        SentryClient.shared.breadcrumb(
            "recording started",
            category: "recording",
            data: [
                "duration_s": "\(Int(duration))",
                "event_id": eventId.uuidString,
            ]
        )

        // Build a clean destination per recording so consecutive takes don't
        // collide. Lives under Documents/events/<eventId>/raw_<timestamp>.mov so
        // it survives app restarts and is reachable for upload later (M3).
        let destination = Self.recordingDestination(eventId: eventId)
        activeRecordingURL = destination

        // Kick the AVCaptureMovieFileOutput first; even if it throws we still
        // honour the visible countdown timer so the operator doesn't see a frozen UI.
        Task {
            do {
                _ = try await controller.startRecording(to: destination)
            } catch {
                // Simulator / no-camera path. We keep the timer running so the
                // flow still advances and lands on Booth360PassthroughRenderClient,
                // which has its own simulator fallback.
            }
        }

        recordingTask?.cancel()
        recordingTask = Task {
            let startedAt = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startedAt)
                recordingElapsed = elapsed
                if elapsed >= duration { break }
                try? await Task.sleep(for: .milliseconds(100))
            }
            if Task.isCancelled { return }
            await finishRecording()
        }
    }

    private func finishRecording() async {
        Haptics.notify(.success)
        AudioServicesPlaySystemSound(SystemSoundID(1106))
        recording = false
        // P4 — pair with `recording started`. Actual elapsed seconds
        // surfaces any clock drift or early cancellation.
        SentryClient.shared.breadcrumb(
            "recording finished",
            category: "recording",
            data: ["elapsed_s": String(format: "%.1f", recordingElapsed)]
        )

        // Stop the file output FIRST so the .mov finalizes on disk before the
        // session shuts down. If we stop the session first AVFoundation may drop
        // the trailing frames.
        var savedURL: URL?
        do {
            savedURL = try await controller.stopRecording()
        } catch {
            // No active recording (simulator path) — fall back to the planned
            // destination URL even though no file was written. Passthrough client
            // will catch the missing file and switch to mock pipeline.
            savedURL = activeRecordingURL
        }
        controller.stop()

        var job = Booth360Job(
            eventId: eventId,
            settingsSnapshot: ai360,
            brandOverlay: brand
        )
        job.rawVideoLocalURL = savedURL
        app.upsertJob(job)
        app.push(.booth360Processing(jobId: job.id))
    }

    /// Documents/events/<eventId>/raw_<unixSeconds>.mov. Stable per recording,
    /// survives app restarts, addressable for cloud upload in M3.
    private static func recordingDestination(eventId: UUID) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = docs
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
        let filename = "raw_\(Int(Date().timeIntervalSince1970)).mov"
        return folder.appendingPathComponent(filename, isDirectory: false)
    }
}

/// M4: lightweight sheet operator can summon mid-event without leaving the
/// recording screen. Three baked presets + jump to the full settings hub.
private struct QuickPresetsSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let eventId: UUID

    private struct Preset: Identifiable, Hashable {
        let id: String
        let label: String
        let duration: Double
        let quality: VideoQuality
        let speed: Double
        let direction: ClipDirection
        let symbol: String
    }

    // Three presets cover 95% of real events. Operator can still drill into
    // AI360SettingsView for full tuning.
    private let presets: [Preset] = [
        .init(id: "quick", label: "Quick (4s · 720p)",
              duration: 4, quality: .sd720p, speed: 1.0, direction: .forwards,
              symbol: "bolt.fill"),
        .init(id: "standard", label: "Standard (6s · 1080p · slow-mo)",
              duration: 6, quality: .hd1080p, speed: 0.75, direction: .reverse,
              symbol: "video.fill"),
        .init(id: "epic", label: "Epic (10s · 1080p · slow-mo)",
              duration: 10, quality: .hd1080p, speed: 0.5, direction: .reverse,
              symbol: "sparkles.tv.fill"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Quick presets") {
                    ForEach(presets) { preset in
                        Button {
                            apply(preset)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: preset.symbol)
                                    .frame(width: 22)
                                    .foregroundStyle(BoothifyTheme.amber)
                                Text(preset.label)
                                    .foregroundStyle(.white)
                                Spacer()
                                if isActive(preset) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(BoothifyTheme.emerald)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(BoothifyTheme.surface1)

                Section {
                    Button {
                        Haptics.tap()
                        dismiss()
                        // Defer push slightly so the sheet finishes dismissing.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            app.push(.settingsAI360(eventId: eventId))
                        }
                    } label: {
                        Label("All 360 settings…", systemImage: "gearshape.fill")
                    }
                }
                .listRowBackground(BoothifyTheme.surface1)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Quick presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func isActive(_ preset: Preset) -> Bool {
        let s = app.settings(for: eventId).ai360
        return s.recordingDurationSeconds == preset.duration
            && s.videoQuality == preset.quality
            && s.clipSpeed == preset.speed
            && s.clipDirection == preset.direction
    }

    private func apply(_ preset: Preset) {
        var all = app.settings(for: eventId)
        all.ai360.recordingDurationSeconds = preset.duration
        all.ai360.videoQuality = preset.quality
        all.ai360.clipSpeed = preset.speed
        all.ai360.clipDirection = preset.direction
        app.updateSettings(all, for: eventId)
        Haptics.notify(.success)
        dismiss()
    }
}

/// M1: faint rectangle inset ~10% from each edge, indicating the area that
/// will survive `.cinematicExtended` stabilization crop. Corner brackets keep
/// the look minimal — we don't want a full ring competing with the subject.
private struct StabilizationSafeAreaFrame: View {
    var body: some View {
        GeometryReader { proxy in
            let inset = min(proxy.size.width, proxy.size.height) * 0.05
            let rect = CGRect(
                x: inset,
                y: inset,
                width: proxy.size.width - inset * 2,
                height: proxy.size.height - inset * 2
            )
            let bracket = min(rect.width, rect.height) * 0.06

            Path { p in
                // Four corner brackets — minimal, low-distraction guide.
                // Top-left
                p.move(to: CGPoint(x: rect.minX, y: rect.minY + bracket))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.minX + bracket, y: rect.minY))
                // Top-right
                p.move(to: CGPoint(x: rect.maxX - bracket, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + bracket))
                // Bottom-right
                p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - bracket))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.maxX - bracket, y: rect.maxY))
                // Bottom-left
                p.move(to: CGPoint(x: rect.minX + bracket, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bracket))
            }
            .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .shadow(color: .black.opacity(0.6), radius: 3, y: 1)
        }
    }
}

#Preview {
    NavigationStack {
        Booth360RecordingView(eventId: UUID())
    }
    .environment(AppState())
}
