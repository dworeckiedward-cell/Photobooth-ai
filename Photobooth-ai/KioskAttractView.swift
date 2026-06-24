import SwiftUI

/// Full-screen "attract" loop shown at the root while Kiosk Mode is active. The
/// whole screen is a tap target that starts the guest capture flow for the event.
/// Exit is deliberately hard to hit by accident: a long-press on the top corner,
/// gated by the event's Lock PIN (or a confirm when no PIN is set).
struct KioskAttractView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventId: UUID

    @State private var pulse = false
    @State private var pinGate = false
    @State private var confirmExit = false
    @State private var showExitHint = false

    private var title: String {
        app.events.first(where: { $0.id == eventId })?.name ?? "Photo Booth"
    }
    private var subtitle: String {
        Loc.t("Tap anywhere to begin", pl: "Dotknij, aby zacząć", de: "Zum Starten tippen")
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            RadialGradient(
                colors: [BoothifyTheme.violet.opacity(0.28), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: BoothifySpacing.lg) {
                Spacer()

                Image(systemName: "camera.aperture")
                    .font(.system(size: 76, weight: .thin))
                    .foregroundStyle(BoothifyTheme.violet)
                    .scaleEffect(pulse ? 1.06 : 0.97)
                    .shadow(color: BoothifyTheme.violet.opacity(0.5), radius: 24)

                VStack(spacing: BoothifySpacing.sm) {
                    Text(title)
                        .font(BoothifyType.display)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }
                .padding(.horizontal, BoothifySpacing.lg)

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                    Text(Loc.t("Tap to start", pl: "Zacznij", de: "Tippen zum Starten"))
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 28).padding(.vertical, 16)
                .background(BoothifyTheme.violet, in: Capsule())
                .opacity(pulse ? 1 : 0.82)
                .padding(.bottom, BoothifySpacing.xl)

                Text("Powered by Boothify")
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .padding(.bottom, BoothifySpacing.lg)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap(.medium)
            app.push(.camera(eventId: eventId))
        }
        // Discreet exit — long-press the top-left corner.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 80, height: 80)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 1.0) { requestExit() }
                .accessibilityLabel("Exit kiosk mode")
                .accessibilityHint("Double-tap and hold to exit")
        }
        // First-entry hint so the operator learns the hidden exit gesture.
        .overlay(alignment: .topLeading) {
            if showExitHint {
                HStack(spacing: 6) {
                    Image(systemName: "hand.point.up.left.fill").font(.caption2)
                    Text(Loc.t("Hold here to exit", pl: "Przytrzymaj, aby wyjść", de: "Halten zum Beenden"))
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .padding(.top, 12).padding(.leading, 12)
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            KioskManager.beginKeepAwake()
            KioskManager.requestSingleAppMode(true)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
            // Show the exit-gesture hint once, then auto-dismiss.
            let key = "boothify.kiosk.exitHintShown"
            if !UserDefaults.standard.bool(forKey: key) {
                UserDefaults.standard.set(true, forKey: key)
                withAnimation { showExitHint = true }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    withAnimation { showExitHint = false }
                }
            }
        }
        .onDisappear { KioskManager.endKeepAwake() }
        .fullScreenCover(isPresented: $pinGate) {
            PinGateView(eventId: eventId) {
                pinGate = false
                exit()
            }
        }
        .confirmationDialog("Exit kiosk mode?", isPresented: $confirmExit, titleVisibility: .visible) {
            Button("Exit", role: .destructive) { exit() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func requestExit() {
        Haptics.tap(.heavy)
        if app.settings(for: eventId).lockPin.enabled {
            pinGate = true
        } else {
            confirmExit = true
        }
    }

    private func exit() {
        KioskManager.requestSingleAppMode(false)
        app.exitKiosk()
    }
}
