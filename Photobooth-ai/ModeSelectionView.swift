import SwiftUI

struct ModeSelectionView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // ── Tier badges row ────────────────────────────────────
                    tierBadgesRow
                        .padding(.top, BoothifySpacing.md)
                        .padding(.horizontal, BoothifySpacing.md)
                        .padding(.bottom, BoothifySpacing.lg)

                    // ── Cards ──────────────────────────────────────────────
                    VStack(spacing: BoothifySpacing.sm) {
                        // Primary: AI Photobooth — tall, dominant
                        ModeTile(
                            title: "AI Photobooth",
                            tagline: "22 cinematic styles. Instant results.",
                            cta: "Start session",
                            ctaSymbol: "arrow.right",
                            asset: "Mode_Photobooth",
                            badge: .live,
                            cardHeight: 340,
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
                            ctaSymbol: "arrow.right",
                            asset: "Mode_360",
                            badge: .beta,
                            cardHeight: 220,
                            primary: false
                        ) {
                            Haptics.tap()
                            app.push(.booth360Landing)
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, BoothifySpacing.md)
                    .padding(.bottom, BoothifySpacing.xl)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Tier badges row

    @ViewBuilder
    private var tierBadgesRow: some View {
        HStack {
            // PREMIUM badge — left
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.caption2.weight(.bold))
                Text("PREMIUM")
                    .font(.caption.weight(.bold))
                    .kerning(0.6)
            }
            .foregroundStyle(BoothifyTheme.violet)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(BoothifyTheme.violet.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.violet.opacity(0.40), lineWidth: 1))

            Spacer()

            // PRO badge — right
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.caption2.weight(.bold))
                Text("PRO")
                    .font(.caption.weight(.bold))
                    .kerning(0.6)
            }
            .foregroundStyle(BoothifyTheme.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(BoothifyTheme.surface1, in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.surfaceLine, lineWidth: 1))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Boothify — Premium Pro account")
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
            switch self { case .live: BoothifyTheme.violet; case .beta: BoothifyTheme.amber }
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
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(
            primary
                ? BoothifyTheme.violet
                : Color.black.opacity(0.50),
            in: Capsule()
        )
        .overlay(
            Capsule().stroke(
                primary ? Color.clear : BoothifyTheme.violet.opacity(0.65),
                lineWidth: 1.5
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
