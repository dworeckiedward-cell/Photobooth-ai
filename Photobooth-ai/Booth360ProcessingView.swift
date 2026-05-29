import SwiftUI

/// 360 AI Booth render-pipeline progress screen. Reads from the live job in
/// `AppState.booth360Jobs`, drives the mock client, and pushes the result
/// screen on completion. When the real backend ships, the only change is
/// swapping `MockBooth360RenderClient.shared` for an API client — the view
/// already polls the job model.
struct Booth360ProcessingView: View {
    @Environment(AppState.self) private var app
    let jobId: UUID

    @State private var pipelineTask: Task<Void, Never>?
    @State private var didNavigate: Bool = false

    private var job: Booth360Job? { app.job(id: jobId) }

    private let steps: [Booth360ProcessingStep] = Booth360ProcessingStep.allCases

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            ambientGlow

            ScrollView {
                VStack(spacing: 26) {
                    titleBlock
                    progressRing
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
            // Kick off the render pipeline once; subsequent appears (e.g. swipe-back
            // during nav animation) shouldn't restart it.
            //
            // IM0: local FFmpeg client is the primary renderer (real montage via
            // h264_videotoolbox). On non-zero return code it falls back to the
            // passthrough renderer internally so the operator never sits on a
            // spinner. The cloud client (M3) still uploads, but only AFTER the
            // local render — kicked off as a side effect once finalVideoURL is
            // available (handled by ResultView / its caller in a future sprint).
            if pipelineTask == nil, let j = job, !j.status.isTerminal {
                pipelineTask = Task {
                    await Booth360FFmpegRenderClient.shared.runPipeline(jobId: jobId, app: app)
                }
            }
        }
        .onDisappear {
            // Once we've navigated forward, leave the task to finish naturally.
            // If the user backs out, cancel it.
            if !didNavigate { pipelineTask?.cancel() }
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
                .animation(BoothifyMotion.gentle, value: job?.currentStep)
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
                .animation(BoothifyMotion.gentle, value: progressFraction)
            VStack(spacing: 2) {
                Text("\(Int(progressFraction * 100))%")
                    // monospacedDigit so the % counter doesn't jitter
                    // left/right by 1-2pt as digits flip during render —
                    // the operator stares at this for 10s every recording.
                    .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
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
                pipelineTask?.cancel()
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
