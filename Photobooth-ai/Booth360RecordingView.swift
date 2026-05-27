import SwiftUI
import AVFoundation
import AudioToolbox

/// 360 AI Booth recording screen — full-screen camera preview with countdown,
/// fake-recording timer, and beep + haptic feedback. Frontend MVP: we don't
/// actually write a video file; on duration end we create a `Booth360Job` with
/// `rawVideoLocalURL = nil` and push to the Processing screen for the mock
/// pipeline.
struct Booth360RecordingView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var controller = CameraController()
    @State private var countdown: Int? = nil
    @State private var recording: Bool = false
    @State private var recordingElapsed: TimeInterval = 0
    @State private var recordingTask: Task<Void, Never>?
    @State private var permissionDenied: Bool = false

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

            if permissionDenied {
                permissionOverlay
            }

            if let countdown {
                ZStack {
                    Color.black.opacity(0.35).ignoresSafeArea()
                    Text("\(countdown)")
                        .font(.system(size: 220, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 20)
                        .transition(.scale.combined(with: .opacity))
                        .id(countdown)
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
            Button {
                Haptics.tap()
                app.push(.settings360Hub(eventId: eventId))
            } label: {
                glassCircle("gearshape.fill")
            }
            .disabled(recording)
            .opacity(recording ? 0.4 : 1)
            .accessibilityLabel("360 settings")
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
            Text("Platform rotating — keep guests centered")
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
                Text("Tap to start a \(Int(duration))s recording")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.4), in: Capsule())
            }

            recordButton
        }
        .padding(.bottom, 36)
    }

    private var recordingStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
            Text("REC")
                .font(.system(size: 11, weight: .bold))
                .kerning(1.0)
                .foregroundStyle(.white)
            Text(timeString)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().stroke(.red.opacity(0.6), lineWidth: 1))
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
                        .animation(.linear(duration: 0.1), value: recordingElapsed)
                }
                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 86, height: 86)
                // Inner state
                if recording {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.red)
                        .frame(width: 32, height: 32)
                } else {
                    Circle()
                        .fill(.red)
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
                Text("Enable Camera access in Settings to use the 360 booth.")
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

    private func beginCountdown() {
        guard !recording, countdown == nil else { return }
        Haptics.tap(.medium)
        countdown = countdownStart
        Task {
            for value in stride(from: countdownStart, through: 1, by: -1) {
                withAnimation(.easeOut(duration: 0.2)) { countdown = value }
                Haptics.tap(.light)
                // System beep — short audio cue per countdown tick
                AudioServicesPlaySystemSound(SystemSoundID(1306))
                try? await Task.sleep(for: .seconds(1))
            }
            withAnimation { countdown = nil }
            startRecording()
        }
    }

    private func startRecording() {
        recording = true
        recordingElapsed = 0
        Haptics.notify(.success)
        // Audible "start" cue
        AudioServicesPlaySystemSound(SystemSoundID(1057))

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
        controller.stop()

        // Create job (mock raw video URL — backend wiring placeholder).
        let job = Booth360Job(
            eventId: eventId,
            settingsSnapshot: ai360,
            brandOverlay: brand
        )
        app.upsertJob(job)
        app.push(.booth360Processing(jobId: job.id))
    }
}

#Preview {
    NavigationStack {
        Booth360RecordingView(eventId: UUID())
    }
    .environment(AppState())
}
