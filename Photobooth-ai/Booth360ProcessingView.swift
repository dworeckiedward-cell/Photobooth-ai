import SwiftUI

/// 360 AI Booth render-pipeline progress screen. Reads from the live job in
/// `AppState.booth360Jobs`, drives the mock client, and pushes the result
/// screen on completion. When the real backend ships, the only change is
/// swapping `MockBooth360RenderClient.shared` for an API client — the view
/// already polls the job model.
struct Booth360ProcessingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let jobId: UUID

    @State private var didNavigate: Bool = false
    @State private var tipIndex: Int = 0
    @State private var tipTimer: Timer? = nil

    private var job: Booth360Job? { app.job(id: jobId) }

    private let steps: [Booth360ProcessingStep] = Booth360ProcessingStep.allCases

    private let processingTips: [(symbol: String, text: String)] = [
        ("wand.and.stars", "AI is color-grading your 360 footage"),
        ("film.stack", "Stitching frames for smooth playback"),
        ("gauge.with.dots.needle.67percent", "Optimizing for mobile streaming"),
        ("music.note", "Syncing your soundtrack to the video"),
        ("arrow.triangle.2.circlepath", "Applying stabilization passes"),
        ("sparkles", "Final quality check before delivery"),
    ]

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            ambientGlow

            ScrollView {
                VStack(spacing: 26) {
                    titleBlock
                    progressRing
                    if job?.status != .completed && job?.status != .failed {
                        tipBlock
                    }
                    stepsList

                    if job?.status == .failed {
                        failedSection
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle("Creating your 360 video")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: jobId) {
            // Phase 3: the render is owned by AppState.startRender (idempotent,
            // detached from this view) so kiosk "Next guest" / navigation never
            // kills an in-flight export. Native AVFoundation client.
            app.startRender(jobId: jobId)
        }
        .onAppear {
            tipTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { _ in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                    tipIndex = (tipIndex + 1) % processingTips.count
                }
            }
        }
        .onDisappear {
            // Render is AppState-owned — navigating away must NOT cancel it
            // (non-blocking kiosk). Explicit cancel lives on the failed-state
            // Back button only.
            tipTimer?.invalidate()
            tipTimer = nil
        }
        .safeAreaInset(edge: .bottom) {
            if app.isKiosk, job?.status.isTerminal != true {
                Button {
                    Haptics.tap(.medium)
                    app.popToRoot()   // attract; export continues in background
                } label: {
                    Label(
                        Loc.t("Next guest", pl: "Następny gość", de: "Nächster Gast"),
                        systemImage: "person.badge.plus"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .accessibilityHint("Returns to the start screen while the video finishes in the background")
            }
        }
        .onChange(of: job?.status) { _, newValue in
            guard let newValue, newValue == .completed, !didNavigate else { return }
            didNavigate = true
            // Brief beat so the user sees 100% before transition.
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                app.push(.booth360Result(jobId: jobId))
            }
        }
    }

    // MARK: - Title

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Creating your 360 video")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(currentStepLabel)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BoothifyTheme.amber)
                .multilineTextAlignment(.center)
                .animation(reduceMotion ? nil : BoothifyMotion.gentle, value: job?.currentStep)
        }
    }

    private var currentStepLabel: String {
        if job?.status == .completed { return "Done — preparing preview…" }
        if job?.status == .failed { return "Render failed" }
        return job?.currentStep?.label ?? "Queued"
    }

    // MARK: - Big progress ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(BoothifyTheme.surface2, lineWidth: 10)
                .frame(width: 160, height: 160)
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    AngularGradient(
                        colors: [BoothifyTheme.amber, BoothifyTheme.fuchsia, BoothifyTheme.amber],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 160, height: 160)
                .animation(reduceMotion ? nil : BoothifyMotion.gentle, value: progressFraction)
            VStack(spacing: 2) {
                Text("\(Int(progressFraction * 100))%")
                    // monospacedDigit so the % counter doesn't jitter
                    // left/right by 1-2pt as digits flip during render —
                    // the operator stares at this for 10s every recording.
                    .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                Text(job?.status.label ?? "—")
                    .font(.caption2.weight(.semibold))
                    .kerning(0.8)
                    .foregroundStyle(BoothifyTheme.textTertiary)
            }
        }
    }

    private var progressFraction: Double {
        guard let job else { return 0 }
        if job.status == .completed { return 1.0 }
        return job.progress
    }

    // MARK: - Processing tips

    private var tipBlock: some View {
        HStack(spacing: 10) {
            Image(systemName: processingTips[tipIndex].symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BoothifyTheme.amber)
                .frame(width: 20)
            Text(processingTips[tipIndex].text)
                .font(.caption.weight(.medium))
                .foregroundStyle(BoothifyTheme.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BoothifyTheme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .id(tipIndex)  // forces fade transition
        .transition(.opacity)
    }

    // MARK: - Steps list

    private var stepsList: some View {
        VStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.element) { idx, step in
                StepRow(
                    step: step,
                    state: stepState(idx: idx, step: step)
                )
            }
        }
        .padding(14)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
    }

    private func stepState(idx: Int, step: Booth360ProcessingStep) -> StepRow.StateKind {
        guard let job else { return .pending }
        if job.status == .completed { return .done }
        if job.currentStep == step { return .active }
        if let currentIdx = job.currentStep.flatMap({ steps.firstIndex(of: $0) }), idx < currentIdx {
            return .done
        }
        return .pending
    }

    // MARK: - Failed

    private var failedSection: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(.red)
            Text(job?.errorMessage ?? "Something went wrong rendering the 360 video.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Back") {
                Haptics.tap()
                app.cancelRender(jobId: jobId)
                app.pop()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 220)
        }
        .padding(.vertical, 16)
    }

    // MARK: - Ambient glow

    private var ambientGlow: some View {
        ZStack {
            RadialGradient(
                colors: [BoothifyTheme.amber.opacity(0.18), .clear],
                center: .init(x: 0.2, y: 0.15),
                startRadius: 0, endRadius: 460
            )
            RadialGradient(
                colors: [BoothifyTheme.fuchsia.opacity(0.14), .clear],
                center: .init(x: 0.85, y: 0.8),
                startRadius: 0, endRadius: 460
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Step row

private struct StepRow: View {
    enum StateKind: Equatable { case pending, active, done }
    let step: Booth360ProcessingStep
    let state: StateKind

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tintBackground)
                    .frame(width: 36, height: 36)
                if state == .active {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(BoothifyTheme.amber)
                } else if state == .done {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BoothifyTheme.emerald)
                } else {
                    Image(systemName: step.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                }
            }
            Text(step.label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(textColor)
            Spacer()
        }
        .padding(.vertical, 4)
        .opacity(state == .pending ? 0.65 : 1)
    }

    private var tintBackground: Color {
        switch state {
        case .pending: BoothifyTheme.surface2
        case .active:  BoothifyTheme.amber.opacity(0.18)
        case .done:    BoothifyTheme.emerald.opacity(0.16)
        }
    }

    private var textColor: Color {
        switch state {
        case .pending: BoothifyTheme.textSecondary
        case .active:  .white
        case .done:    .white
        }
    }
}

#Preview {
    NavigationStack {
        Booth360ProcessingView(jobId: UUID())
    }
    .environment(AppState())
}
