import SwiftUI

struct ModeSelectionView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Wordmark header ────────────────────────────────────
                    wordmarkHeader
                        .padding(.top, 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)

                    // ── Cards ──────────────────────────────────────────────
                    VStack(spacing: 12) {
                        // Primary: AI Photobooth — tall, dominant
                        ModeTile(
                            title: "AI Photobooth",
                            tagline: "22 cinematic styles. Instant results.",
                            cta: "Start session",
                            ctaSymbol: "arrow.right",
                            asset: "Mode_Photobooth",
                            badge: .live,
                            cardHeight: 320,
                            primary: true
                        ) {
                            Haptics.tap(.medium)
                            app.push(.photoboothLanding)
                        }

                        // Secondary: 360 AI Booth — companion card
                        ModeTile(
                            title: "360 AI Booth",
                            tagline: "Rotating video. AI cinematic effects.",
                            cta: "Preview",
                            ctaSymbol: "play.fill",
                            asset: "Mode_360",
                            badge: .beta,
                            cardHeight: 210,
                            primary: false
                        ) {
                            Haptics.tap()
                            app.push(.booth360Landing)
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Wordmark header

    /// Clean editorial header — logo left, tagline right. No nav bar needed.
    @ViewBuilder
    private var wordmarkHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Boothify")
                    .font(BoothifyType.title)
                    .foregroundStyle(.white)
                    .kerning(-0.3)
                Text("Choose your mode")
                    .font(BoothifyType.caption)
                    .foregroundStyle(BoothifyTheme.textTertiary)
            }
            Spacer()
            // Ambient live indicator — the event is "open for business"
            HStack(spacing: 5) {
                Circle()
                    .fill(BoothifyTheme.emerald)
                    .frame(width: 6, height: 6)
                Text("Ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(BoothifyTheme.surface1, in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.surfaceLine, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Boothify — Choose your mode")
    }
}

// MARK: - ModeTile

private struct ModeTile: View {
    enum TileBadge {
        case live, beta

        var label: String {
            switch self { case .live: "LIVE"; case .beta: "BETA" }
        }
        var tint: Color {
            switch self { case .live: BoothifyTheme.emerald; case .beta: BoothifyTheme.amber }
        }
        var symbol: String {
            switch self { case .live: "circle.fill"; case .beta: "sparkles" }
        }
    }

    let title: String
    let tagline: String
    let cta: String
    let ctaSymbol: String
    let asset: String
    let badge: TileBadge
    let cardHeight: CGFloat
    let primary: Bool
    let action: () -> Void

    @State private var pressed: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            cardBody
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.982 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: pressed)
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: 30,
            perform: {},
            onPressingChanged: { pressing in pressed = pressing }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(tagline)")
        .accessibilityHint("Double-tap to \(cta.lowercased())")
    }

    private var cardBody: some View {
        Rectangle()
            .fill(Color.black)
            // Photo background
            .overlay {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .saturation(primary ? 1.0 : 0.80)
            }
            // Legibility gradient — bottom-heavy for text on top of photo
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.08), location: 0),
                        .init(color: .black.opacity(0.55), location: 0.52),
                        .init(color: .black.opacity(0.94), location: 1.0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            // Subtle brand tint wash at very bottom (deepens depth)
            .overlay {
                LinearGradient(
                    colors: [
                        (primary ? BoothifyTheme.violet : BoothifyTheme.amber).opacity(0.30),
                        .clear,
                    ],
                    startPoint: .bottom,
                    endPoint: .init(x: 0.5, y: 0.6)
                )
            }
            // ── Top-right status badge ──────────────────────────────────
            .overlay(alignment: .topTrailing) {
                BadgePill(badge: badge)
                    .padding(18)
            }
            // ── Bottom content block ────────────────────────────────────
            .overlay(alignment: .bottomLeading) {
                bottomContent
                    .padding(22)
            }
            .frame(height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(primary ? 0.13 : 0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(primary ? 0.45 : 0.30), radius: primary ? 24 : 14, y: primary ? 14 : 8)
    }

    private var bottomContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(primary
                          ? .system(.largeTitle, design: .default, weight: .bold)
                          : .system(.title2, design: .default, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(tagline)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }

            // CTA capsule — solid white on primary, amber-tinted on secondary
            ctaCapsule
        }
    }

    @ViewBuilder
    private var ctaCapsule: some View {
        HStack(spacing: 6) {
            Text(cta)
                .font(.subheadline.weight(.semibold))
            Image(systemName: ctaSymbol)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(primary ? Color.black : BoothifyTheme.amber)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(primary ? Color.white : Color.black.opacity(0.55), in: Capsule())
        .overlay(
            Capsule().stroke(
                primary ? Color.clear : BoothifyTheme.amber.opacity(0.60),
                lineWidth: 1
            )
        )
    }
}

// MARK: - Badge pill

private struct BadgePill: View {
    let badge: ModeTile.TileBadge

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: badge.symbol)
                .font(.caption2.weight(.black))
            Text(badge.label)
                .font(.caption2.weight(.bold))
                .kerning(0.8)
        }
        .foregroundStyle(badge.tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.50), in: Capsule())
        .overlay(Capsule().stroke(badge.tint.opacity(0.50), lineWidth: 0.8))
    }
}

// MARK: - Beta preview sheet (unchanged)

struct BetaPreviewSheet: View {
    let title: String
    let message: String
    let ctaTitle: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(
                            colors: [BoothifyTheme.amber.opacity(0.45), .clear],
                            center: .center, startRadius: 4, endRadius: 80
                        ))
                        .frame(width: 140, height: 140)
                        .blur(radius: 14)
                    Image(systemName: "sparkles")
                        .font(BoothifyType.display)
                        .foregroundStyle(BoothifyTheme.amber)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .padding(.top, 24)

                Text(title)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()

                Button(ctaTitle) {
                    Haptics.tap()
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ModeSelectionView()
    }
    .environment(AppState())
}
