import SwiftUI

/// Full-screen "attract" loop shown at the root while Kiosk Mode is active. The
/// whole screen is a tap target that starts the guest capture flow for the event.
/// Exit is deliberately hard to hit by accident: a long-press on the top corner,
/// gated by the event's Lock PIN (or a confirm when no PIN is set).
///
/// UI-polish pass: the OPERATOR's brand is the hero (their logo/watermark when
/// configured), the 360 accent (amber) carries the screen, and Boothify stays
/// nearly invisible. Runs for hours — motion is calm, seamless, reduce-motion
/// gets a fully static but still inviting variant.
struct KioskAttractView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventId: UUID

    @State private var pulse = false
    @State private var pinGate = false
    @State private var confirmExit = false
    @State private var showExitHint = false

    private var title: String {
        app.events.first(where: { $0.id == eventId })?.name
            ?? Loc.t("360 Booth", pl: "Budka 360", de: "360-Booth")
    }
    private var subtitle: String {
        Loc.t("Tap anywhere to begin", pl: "Dotknij, aby zacząć", de: "Zum Starten tippen")
    }
    private var brand: BrandOverlaySettings { app.settings(for: eventId).brandOverlay }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            RadialGradient(
                colors: [BoothifyTheme.amber.opacity(0.22), .clear],
                center: .top, startRadius: 0, endRadius: 520
            )
            .ignoresSafeArea()

            VStack(spacing: BoothifySpacing.lg) {
                Spacer()

                // The operator's mark is the hero; a 360 glyph is only the
                // fallback when no branding is configured.
                OperatorBrandMark(brand: brand, eventId: eventId)
                    .scaleEffect(pulse ? 1.04 : 0.98)

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

                // Calm reassurance while a previous export finishes — the booth
                // is non-blocking, so the next guest can start right away.
                if app.hasActiveRenders {
                    HStack(spacing: BoothifySpacing.xs + 2) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(BoothifyTheme.amber)
                        Text(Loc.t(
                            "Previous video is finishing — you can start",
                            pl: "Poprzednie wideo się kończy — możesz zaczynać",
                            de: "Das letzte Video wird fertig — du kannst starten"
                        ))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(BoothifyTheme.textSecondary)
                    }
                    .padding(.horizontal, BoothifySpacing.md)
                    .padding(.vertical, BoothifySpacing.sm)
                    .background(.black.opacity(0.45), in: Capsule())
                    .overlay(Capsule().stroke(BoothifyTheme.surfaceLine, lineWidth: 1))
                    .transition(.opacity)
                    .accessibilityLabel(Loc.t(
                        "Previous video is finishing in the background. You can start.",
                        pl: "Poprzednie wideo kończy się w tle. Możesz zaczynać.",
                        de: "Das letzte Video wird im Hintergrund fertig. Du kannst starten."
                    ))
                }

                HStack(spacing: BoothifySpacing.sm) {
                    Image(systemName: "hand.tap.fill")
                    Text(Loc.t("Tap to start", pl: "Zacznij", de: "Tippen zum Starten"))
                        .fontWeight(.semibold)
                }
                .font(.headline)
                .foregroundStyle(.black)
                .padding(.horizontal, BoothifySpacing.lg)
                .padding(.vertical, BoothifySpacing.md)
                .background(BoothifyTheme.amber, in: Capsule())
                .opacity(pulse ? 1 : 0.85)
                .padding(.bottom, BoothifySpacing.xl)

                // Boothify stays nearly invisible on the operator's stage.
                Text("Boothify")
                    .font(.caption2)
                    .foregroundStyle(BoothifyTheme.textMuted.opacity(0.6))
                    .padding(.bottom, BoothifySpacing.lg)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap(.medium)
            app.push(.booth360Recording(eventId: eventId))
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
                HStack(spacing: BoothifySpacing.xs + 2) {
                    Image(systemName: "hand.point.up.left.fill").font(.caption2)
                    Text(Loc.t("Hold here to exit", pl: "Przytrzymaj, aby wyjść", de: "Halten zum Beenden"))
                        .font(.caption.weight(.medium))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, BoothifySpacing.sm + 4).padding(.vertical, BoothifySpacing.sm)
                .background(.black.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 1))
                .padding(.top, BoothifySpacing.sm + 4).padding(.leading, BoothifySpacing.sm + 4)
                .transition(.opacity)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            KioskManager.beginKeepAwake()
            KioskManager.requestSingleAppMode(true)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
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

/// The operator's brand as the attract hero: uploaded logo → sample asset →
/// watermark text → 360 glyph fallback. Sized to read from meters away.
private struct OperatorBrandMark: View {
    let brand: BrandOverlaySettings
    let eventId: UUID

    var body: some View {
        Group {
            if brand.enabled, let logo = resolvedLogo() {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 220, maxHeight: 120)
            } else if brand.enabled, brand.logoSource == .textFallback,
                      !brand.overlayText.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(brand.overlayText)
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            } else {
                Image(systemName: "rotate.3d.fill")
                    .font(.system(size: 76, weight: .thin))
                    .foregroundStyle(BoothifyTheme.amber)
                    .shadow(color: BoothifyTheme.amber.opacity(0.45), radius: 24)
            }
        }
        .accessibilityHidden(true)
    }

    private func resolvedLogo() -> UIImage? {
        switch brand.logoSource {
        case .boothifySample:
            return UIImage(named: brand.logoAssetName ?? "BoothifyLogo")
        case .uploaded:
            guard let relative = brand.customLogoRelativePath else { return nil }
            let url = RenderDecorationsBuilder.eventDirectory(eventId: eventId)
                .appendingPathComponent(relative)
            return UIImage(contentsOfFile: url.path)
        case .textFallback:
            return nil
        }
    }
}
