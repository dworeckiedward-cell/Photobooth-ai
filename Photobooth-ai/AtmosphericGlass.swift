import SwiftUI

// ATMOSPHERIC GLASS — the visual-language foundation (UI brief v2).
// Dark full-bleed atmosphere + frosted glass surfaces + soft accent glows.
// Everything here is presentation-only and cascades through the app via
// the shared components (AppCard / Surface / SettingsCard / nav) that now
// consume it. Screens should NEVER hand-roll glass or backgrounds.

// MARK: - Atmospheric background

/// Full-bleed dark backdrop under every screen. Placeholder: a deep
/// violet/indigo gradient mesh with a whisper of warm amber — replaceable by
/// an operator asset later (`assetName` hook; no upload system yet, by brief).
/// A scrim guarantees white-text legibility top and bottom.
struct AtmosphericBackground: View {
    /// Future operator-branding hook: bundle/document asset name. When nil or
    /// missing, the built-in mesh renders.
    var assetName: String? = nil

    var body: some View {
        ZStack {
            BoothifyTheme.bgDeep.ignoresSafeArea()

            if let assetName, let image = UIImage(named: assetName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            } else {
                mesh
            }

            // Legibility scrim — dark pressure top & bottom so large white
            // type never fights the atmosphere (brief §4).
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .clear, location: 0.65),
                    .init(color: .black.opacity(0.45), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Black era: a truly dark stage — only a faint violet pool at the top
    /// edge (bento reference), so calendar/settings read as black screens.
    /// Static by design — atmosphere breathes through space, not motion.
    private var mesh: some View {
        RadialGradient(
            colors: [BoothifyTheme.indigoGlow.opacity(0.20), .clear],
            center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 460
        )
        .ignoresSafeArea()
    }
}

// MARK: - Glass surface

/// THE surface of the language: frosted material floating over the
/// atmosphere, 1px light rim, continuous radius, soft drop.
/// Accessibility: Reduce Transparency degrades to a SOLID dark surface
/// (mandatory fallback — glass must never cost legibility).
struct GlassSurface: ViewModifier {
    var radius: CGFloat = BoothifyRadius.surface

    func body(content: Content) -> some View {
        content
            .background {
                if UIAccessibility.isReduceTransparencyEnabled {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(BoothifyTheme.bgElevated)
                } else {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .shadow(color: .black.opacity(0.30), radius: 16, y: 8)
    }
}

extension View {
    /// Frosted glass panel — the one way surfaces float in Boothify.
    func glassSurface(radius: CGFloat = BoothifyRadius.surface) -> some View {
        modifier(GlassSurface(radius: radius))
    }
}

// MARK: - Glow accent

/// Soft radial glow behind a key action (capture, QR, primary CTA). One glow
/// per screen — the accent is scarce by design. Static (no pulsing here;
/// screens that pulse already guard reduce-motion).
struct GlowAccent: ViewModifier {
    var color: Color = BoothifyTheme.violet
    /// 0…1 — how loud the glow is. 0.35 whisper, 0.7 hero.
    var intensity: Double = 0.5

    func body(content: Content) -> some View {
        content
            .background(
                Circle()
                    .fill(color.opacity(0.55 * intensity))
                    .blur(radius: 36)
                    .scaleEffect(1.6)
            )
            .shadow(color: color.opacity(0.45 * intensity), radius: 24)
    }
}

extension View {
    func glowAccent(color: Color = BoothifyTheme.violet, intensity: Double = 0.5) -> some View {
        modifier(GlowAccent(color: color, intensity: intensity))
    }
}
