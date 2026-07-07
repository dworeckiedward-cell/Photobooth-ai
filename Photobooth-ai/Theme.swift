import SwiftUI

// MARK: - Colour tokens

enum BoothifyTheme {
    // Backgrounds
    static let bg          = Color(red: 0.04, green: 0.04, blue: 0.05)   // ~zinc-950
    // Atmospheric Glass (UI v2): the deep violet/indigo stage every screen
    // floats on, plus the solid surface glass degrades to under
    // Reduce Transparency.
    // Black era: the stage is near-black with only a whisper of violet
    // (bento reference) — no more saturated indigo mesh.
    static let bgDeep      = Color(red: 0.031, green: 0.020, blue: 0.059) // near-black, violet cast
    static let bgElevated  = Color(red: 0.08, green: 0.07, blue: 0.12)    // solid glass fallback
    static let indigoGlow  = Color(red: 0.24, green: 0.20, blue: 0.55)    // mesh pool hue (dim use only)
    static let surface1    = Color.white.opacity(0.05)
    static let surface2    = Color.white.opacity(0.08)
    static let surfaceLine = Color.white.opacity(0.10)

    // Text hierarchy
    static let textPrimary    = Color.white
    static let textSecondary  = Color(red: 0.65, green: 0.66, blue: 0.70)  // zinc-400
    // Bumped for WCAG AA legibility on the true-black background (small captions):
    static let textTertiary   = Color(red: 0.52, green: 0.53, blue: 0.57)  // ~zinc-450
    static let textMuted      = Color(red: 0.42, green: 0.43, blue: 0.47)  // ~zinc-500

    // Accent palette
    // Atmospheric Glass palette-drift fix: this token spent an era as
    // blue-500, bleeding a foreign blue across settings, panels and the tab
    // bar. It is now a TRUE violet from the atmosphere family — quiet
    // support only. Amber remains the one interaction accent.
    static let violet  = Color(red: 0.545, green: 0.408, blue: 0.965)    // violet-500
    static let fuchsia = Color(red: 0.851, green: 0.275, blue: 0.937)    // kept for backward-compat; prefer violet in UI
    static let pink    = Color(red: 0.925, green: 0.282, blue: 0.6)      // legacy; do not use in new UI
    static let emerald = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let amber   = Color(red: 0.960, green: 0.620, blue: 0.043)    // 360-mode accent only

    // Semantic
    static let error   = Color(red: 0.96, green: 0.27, blue: 0.32)       // ~red-500, 4.5:1 on bg ✓
    /// REC indicator red — the one place raw red is part of the language
    /// (universal recording convention), tokenized so views never hardcode it.
    static let recording = Color(red: 0.94, green: 0.20, blue: 0.20)
    static let warning = amber
    static let success = emerald

    // Monochrome Pro: gradients are photo/video-only.
    // These are kept so existing call-sites still compile but should not
    // appear on chrome — only on generated imagery.
    static let primaryGradient = LinearGradient(
        colors: [violet, fuchsia],
        startPoint: .leading,
        endPoint: .trailing
    )
    static let headingGradient = LinearGradient(
        colors: [Color.white, Color.white, Color(white: 0.45)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Radius tokens

enum BoothifyRadius {
    static let micro:   CGFloat = 8
    static let input:   CGFloat = 12
    static let tile:    CGFloat = 14
    static let card:    CGFloat = 16
    static let section: CGFloat = 18
    static let surface: CGFloat = 20
    static let hero:    CGFloat = 24
}

// MARK: - Spacing tokens

enum BoothifySpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
}

// MARK: - Button styles

/// Full-width primary action button.
/// Monochrome Pro: solid white fill, black text — no gradients on chrome.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BoothifyType.bodyEmphasis)
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(Color.white.opacity(configuration.isPressed ? 0.88 : 1))
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Violet-tinted accent button (use sparingly — one per screen maximum).
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BoothifyType.bodyEmphasis)
            .foregroundStyle(Color.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(BoothifyTheme.violet.opacity(configuration.isPressed ? 0.80 : 1))
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Accent hero CTA — THE glowing action of a screen (black era: violet).
/// White-on-violet capsule; pair with `.glowAccent()` and keep it to one
/// per screen — the accent is scarce by design.
struct AccentCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BoothifyType.bodyEmphasis)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                LinearGradient(
                    colors: [BoothifyTheme.violet, BoothifyTheme.violet.opacity(0.78)],
                    startPoint: .top, endPoint: .bottom
                )
                .opacity(configuration.isPressed ? 0.85 : 1),
                in: Capsule()
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Ghost secondary button with hairline border.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BoothifyType.subheadline.weight(.semibold))
            .foregroundStyle(BoothifyTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(BoothifyTheme.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

/// Compact icon + label tile (2×2 grid of secondary actions).
struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(BoothifyTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(BoothifyTheme.surface2.opacity(configuration.isPressed ? 0.6 : 1))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

// MARK: - Surfaces

struct Surface: ViewModifier {
    var elevated: Bool = false
    var radius: CGFloat = BoothifyRadius.surface
    func body(content: Content) -> some View {
        // Atmospheric Glass: the legacy Surface now IS glass, so every
        // .boothifySurface call-site cascades to the new language for free.
        content.glassSurface(radius: radius)
    }
}

extension View {
    func boothifySurface(elevated: Bool = false, radius: CGFloat = BoothifyRadius.surface) -> some View {
        modifier(Surface(elevated: elevated, radius: radius))
    }
}

// MARK: - Headings

/// Plain white heading — Monochrome Pro standard.
/// Use `GradientHeading` only on photo/video results, never on chrome.
struct Heading: View {
    let text: String
    var font: Font = BoothifyType.display
    var body: some View {
        Text(text)
            .font(font)
            .kerning(-0.5)
            .foregroundStyle(BoothifyTheme.textPrimary)
    }
}

/// Legacy gradient heading — retained for backward-compat.
/// New code should use `Heading` or plain `Text` with `.foregroundStyle(.white)`.
struct GradientHeading: View {
    let text: String
    var font: Font = BoothifyType.display
    var body: some View {
        Text(text)
            .font(font)
            .kerning(-0.5)
            .foregroundStyle(BoothifyTheme.textPrimary)   // Monochrome Pro: white, no gradient
    }
}

// MARK: - Shared components
//
// Note: StatTile has per-file private implementations in EventHubView and
// Booth360EventHubView with a different signature — do not add a global
// StatTile here to avoid redeclaration errors.

/// Reusable empty-state view used across gallery, cloud panel, etc.
/// Layout redesign: a composed leading-aligned statement on light glass,
/// not an orphaned icon floating in the middle of a void.
struct BoothifyEmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)? = nil
    var actionLabel: String = "Get started"

    var body: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.md) {
            HStack(spacing: BoothifySpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .fill(BoothifyTheme.amber.opacity(0.10))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.amber.opacity(0.75))
                }
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(BoothifyType.bodyEmphasis)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(BoothifyType.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let action {
                Button(actionLabel, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 200)
            }
        }
        .padding(BoothifySpacing.md)
        .frame(maxWidth: 480)
        .glassSurface(radius: BoothifyRadius.section)
        .padding(BoothifySpacing.lg)
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        let gen = UIImpactFeedbackGenerator(style: style)
        gen.prepare()
        gen.impactOccurred()
    }

    static func notify(_ kind: UINotificationFeedbackGenerator.FeedbackType) {
        let gen = UINotificationFeedbackGenerator()
        gen.prepare()
        gen.notificationOccurred(kind)
    }

    static func selection() {
        let gen = UISelectionFeedbackGenerator()
        gen.prepare()
        gen.selectionChanged()
    }
}
