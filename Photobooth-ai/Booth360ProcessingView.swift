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

    private var processingTips: [(symbol: String, text: String)] {
        [
            ("sparkles", Loc.t("Your spin is being rendered", pl: "Twój spin właśnie się renderuje", de: "Dein Spin wird gerendert")),
            ("film.stack", Loc.t("Every frame gets the slow-mo treatment", pl: "Każda klatka dostaje slow motion", de: "Jedes Bild bekommt die Zeitlupe")),
            ("music.note", Loc.t("Music is being woven in", pl: "Muzyka właśnie się wplata", de: "Die Musik wird eingewoben")),
            ("iphone.gen3", Loc.t("Sized perfectly for your phone", pl: "Idealny rozmiar na telefon", de: "Perfekt fürs Handy dimensioniert")),
            ("qrcode", Loc.t("Your QR code is seconds away", pl: "Twój kod QR za kilka sekund", de: "Dein QR-Code kommt gleich")),
        ]
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            // Layout redesign: one calm hero of motion — the big ring — and
            // nothing but whispers around it. No tip brick, no steps brick;
            // the atmosphere carries the wait.
            VStack(spacing: 0) {
                Spacer(minLength: BoothifySpacing.xl)

                titleBlock

                Spacer()

                progressRing

                stepDots
                    .padding(.top, BoothifySpacing.lg)

                Spacer()

                if job?.status == .failed {
                    failedSection
                        .padding(.horizontal, BoothifySpacing.lg)
                } else if job?.status != .completed {
                    tipLine
                        .padding(.horizontal, BoothifySpacing.xl)
                }

                Spacer(minLength: BoothifySpacing.xxl)
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
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
                VStack(spacing: BoothifySpacing.xs + 2) {
                    Text(Loc.t(
                        "The video will finish in the background",
                        pl: "Wideo dokończy się w tle",
                        de: "Das Video wird im Hintergrund fertig"
                    ))
                    .font(.caption)
                    .foregroundStyle(BoothifyTheme.textTertiary)
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
                .accessibilityHint("Returns to the start screen while the video finishes in the background")
                }
                .padding(.horizontal, BoothifySpacing.lg)
                .padding(.bottom, BoothifySpacing.sm + 4)
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
            Text(Loc.t("Creating your 360 video", pl: "Tworzę Twoje wideo 360", de: "Dein 360-Video entsteht"))
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
        if job?.status == .completed { return Loc.t("Done — preparing preview…", pl: "Gotowe — przygotowuję podgląd…", de: "Fertig — Vorschau wird geladen…") }
        if job?.status == .failed { return Loc.t("Something went wrong", pl: "Coś poszło nie tak", de: "Etwas ist schiefgelaufen") }
        return job?.currentStep?.label ?? Loc.t("Queued", pl: "W kolejce", de: "In der Warteschlange")
    }

    // MARK: - Big progress ring

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(BoothifyTheme.surface2, lineWidth: 12)
                .frame(width: 220, height: 220)
            Circle()
                .trim(from: 0, to: progressFraction)
                .stroke(
                    AngularGradient(
                        colors: [BoothifyTheme.amber.opacity(0.35), BoothifyTheme.amber, BoothifyTheme.amber],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 220, height: 220)
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
        // The screen's one glow — the ring IS the hero of motion.
        .glowAccent(intensity: 0.28)
    }

    // MARK: - Step dots (quiet progression, replaces the steps brick)

    private var stepDots: some View {
        HStack(spacing: BoothifySpacing.sm) {
            ForEach(Array(steps.enumerated()), id: \.element) { idx, step in
                Circle()
                    .fill(dotColor(idx: idx, step: step))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(currentStepLabel)
    }

    private func dotColor(idx: Int, step: Booth360ProcessingStep) -> Color {
        switch stepState(idx: idx, step: step) {
        case .done:    BoothifyTheme.amber.opacity(0.9)
        case .active:  BoothifyTheme.amber
        case .pending: BoothifyTheme.surface2
        }
    }

    private var progressFraction: Double {
        guard let job else { return 0 }
        if job.status == .completed { return 1.0 }
        return job.progress
    }

    // MARK: - Processing tips (a floating whisper, not a card)

    private var tipLine: some View {
        HStack(spacing: 8) {
            Image(systemName: processingTips[tipIndex].symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BoothifyTheme.amber)
            Text(processingTips[tipIndex].text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(BoothifyTheme.textSecondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .id(tipIndex)  // forces fade transition
        .transition(.opacity)
    }

    // MARK: - Step progression state

    private enum StepState { case pending, active, done }

    private func stepState(idx: Int, step: Booth360ProcessingStep) -> StepState {
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
        VStack(spacing: BoothifySpacing.sm + 2) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundStyle(BoothifyTheme.error)
                .accessibilityHidden(true)
            Text(job?.errorMessage ?? Loc.t(
                "Something went wrong rendering the video.",
                pl: "Coś poszło nie tak przy renderowaniu wideo.",
                de: "Beim Rendern des Videos ist etwas schiefgelaufen."
            ))
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
            // The raw take is KEPT on failure precisely so a retry is possible.
            Button {
                Haptics.tap(.medium)
                app.cancelRender(jobId: jobId)
                app.startRender(jobId: jobId)
            } label: {
                Label(Loc.t("Try again", pl: "Spróbuj ponownie", de: "Erneut versuchen"),
                      systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AccentButtonStyle())
            .frame(maxWidth: 220)
            Button(Loc.t("Back", pl: "Wróć", de: "Zurück")) {
                Haptics.tap()
                app.cancelRender(jobId: jobId)
                app.pop()
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(maxWidth: 220)
        }
        .padding(.vertical, BoothifySpacing.md)
    }

}

#Preview {
    NavigationStack {
        Booth360ProcessingView(jobId: UUID())
    }
    .environment(AppState())
}
