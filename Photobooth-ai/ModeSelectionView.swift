import SwiftUI

struct ModeSelectionView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    headlineBlock
                        .padding(.top, 4)

                    VStack(spacing: 14) {
                        ModeTile(
                            title: "AI Photobooth",
                            description: "Capture guests and transform them into 10 cinematic AI styles.",
                            cta: "Start session",
                            symbol: "camera.aperture",
                            asset: "Mode_Photobooth",
                            badge: .available,
                            primary: true
                        ) {
                            Haptics.tap(.medium)
                            app.push(.photoboothLanding)
                        }

                        ModeTile(
                            title: "360 AI Booth",
                            description: "Rotating 360° video with AI-powered cinematic effects.",
                            cta: "Preview mode",
                            symbol: "video.fill",
                            asset: "Mode_360",
                            badge: .beta,
                            primary: false
                        ) {
                            Haptics.tap()
                            app.push(.booth360Landing)
                        }
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, 16)

                    Text("Powered by Servify Labs")
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, 2)
                        .padding(.bottom, 28)
                }
                .frame(maxWidth: .infinity)
            }
        }
        // Hide the entire nav bar (this view is the root, no back action needed) and
        // mount a non-interactive wordmark in a thin safe-area inset, positioned
        // visually between the left time area and the Dynamic Island. Decorative —
        // no button, no container, no background, just a small text mark.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { microBrand }
    }

    @ViewBuilder
    private var headlineBlock: some View {
        VStack(spacing: 6) {
            GradientHeading(text: "Choose your mode", font: BoothifyType.displayMedium)
                .multilineTextAlignment(.center)
            Text("Create cinematic AI portraits or launch a premium 360° booth experience.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
                .padding(.horizontal, 24)
        }
    }

    /// Decorative top brand mark. Lives in a thin safeAreaInset strip below the
    /// system status bar, offset horizontally so it visually sits to the left of
    /// the Dynamic Island. No background, no container, no tap target.
    @ViewBuilder
    private var microBrand: some View {
        Text("Boothify")
            .font(BoothifyType.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.80))
            .kerning(0.3)
            .padding(.leading, 130)   // pushes wordmark to x ≈ 130, ending at ~180
            .padding(.top, 8)
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel("Boothify")
    }
}

// MARK: - ModeTile

private struct ModeTile: View {
    enum TileBadge {
        case available, beta

        var label: String {
            switch self { case .available: "AVAILABLE"; case .beta: "BETA" }
        }
        var subLabel: String {
            switch self { case .available: ""; case .beta: "Private preview" }
        }
        var tint: Color {
            switch self { case .available: BoothifyTheme.emerald; case .beta: BoothifyTheme.amber }
        }
        var symbol: String {
            switch self { case .available: "checkmark.seal.fill"; case .beta: "sparkles" }
        }
    }

    let title: String
    let description: String
    let cta: String
    let symbol: String
    let asset: String
    let badge: TileBadge
    let primary: Bool
    let action: () -> Void

    @State private var pressed: Bool = false

    var body: some View {
        Button {
            action()
        } label: {
            cardBody
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.985 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 30, perform: {}, onPressingChanged: { isPressing in
            pressed = isPressing
        })
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(description)")
        .accessibilityHint("\(cta), \(badge.label)")
    }

    private var cardBody: some View {
        Rectangle()
            .fill(Color.black)
            .overlay {
                Image(asset)
                    .resizable()
                    .scaledToFill()
                    .saturation(primary ? 1.0 : 0.85)
            }
            // Dark legibility overlay
            .overlay {
                LinearGradient(
                    colors: primary
                        ? [.black.opacity(0.40), .black.opacity(0.62), .black.opacity(0.92)]
                        : [.black.opacity(0.55), .black.opacity(0.75), .black.opacity(0.95)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            // Brand wash from bottom
            .overlay {
                LinearGradient(
                    colors: [
                        Color(red: 0.20, green: 0.08, blue: 0.38).opacity(primary ? 0.55 : 0.30),
                        .clear
                    ],
                    startPoint: .bottom, endPoint: .center
                )
            }
            // Top row: icon badge + status badge
            .overlay(alignment: .topLeading) {
                HStack(alignment: .top) {
                    Image(systemName: symbol)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.white.opacity(0.30), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                        .accessibilityHidden(true)
                    Spacer()
                    StatusBadge(badge: badge)
                }
                .padding(20)
            }
            // Bottom content
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(BoothifyType.displayMedium)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(cta)
                            .font(.body.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(primary ? .white : BoothifyTheme.amber)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .frame(height: primary ? 260 : 220)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(primary ? 0.14 : 0.10), lineWidth: 1)
            )
            // Subtle violet glow only on the primary card
            .shadow(color: primary ? BoothifyTheme.violet.opacity(0.30) : .black.opacity(0.35), radius: primary ? 22 : 16, y: 12)
    }
}

private struct StatusBadge: View {
    let badge: ModeTile.TileBadge

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: badge.symbol)
                    .font(.caption2.weight(.bold))
                Text(badge.label)
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
            }
            .foregroundStyle(badge.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(badge.tint.opacity(0.18), in: Capsule())
            .overlay(Capsule().stroke(badge.tint.opacity(0.55), lineWidth: 0.8))

            if !badge.subLabel.isEmpty {
                Text(badge.subLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.4), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Beta preview sheet

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
