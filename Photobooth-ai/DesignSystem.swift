import SwiftUI

// MARK: - AppCard
/// Reusable surface card. Replaces the scattered .background(surface1) + .overlay(border) pattern.
struct AppCard<Content: View>: View {
    var padding: CGFloat = BoothifySpacing.lg
    var radius: CGFloat = BoothifyRadius.surface
    @ViewBuilder var content: () -> Content

    var body: some View {
        // Atmospheric Glass: every card floats as frosted material (solid
        // fallback under Reduce Transparency lives inside glassSurface).
        content()
            .padding(padding)
            .glassSurface(radius: radius)
    }
}

// MARK: - AppGlassCard
/// Ultra-thin material card — use on top of photos or saturated backgrounds.
struct AppGlassCard<Content: View>: View {
    var padding: CGFloat = BoothifySpacing.lg
    var radius: CGFloat = BoothifyRadius.hero
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

// MARK: - AppIconBadge
/// Tinted SF Symbol icon in a rounded-rect container. Consistent across all screens.
struct AppIconBadge: View {
    let symbol: String
    var color: Color = BoothifyTheme.violet
    var size: CGFloat = 40
    var background: Color? = nil

    private var cornerRadius: CGFloat { size * 0.28 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(background ?? color.opacity(0.14))
                .frame(width: size, height: size)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(color.opacity(0.22), lineWidth: 1)
                )
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(color)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - AppSectionHeader
/// Eyebrow label + title with an optional trailing action. Place above every major card section.
struct AppSectionHeader: View {
    var eyebrow: String? = nil
    let title: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .kerning(1.4)
                    .foregroundStyle(BoothifyTheme.textTertiary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(BoothifyType.title)
                    .foregroundStyle(.white)
                Spacer()
                if let label = actionLabel, let action {
                    Button(action: { Haptics.tap(.light); action() }) {
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(BoothifyTheme.violet)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - AppEmptyState
/// Consistent empty state: icon badge + headline + subtitle copy + optional CTA.
struct AppEmptyState: View {
    let symbol: String
    var symbolColor: Color = BoothifyTheme.textMuted
    let title: String
    let subtitle: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: BoothifySpacing.md) {
            AppIconBadge(symbol: symbol, color: symbolColor, size: 52)
                .padding(.bottom, 2)
            VStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let label = actionLabel, let action {
                Button(label, action: action)
                    .buttonStyle(SecondaryButtonStyle())
                    .frame(maxWidth: 200)
                    .padding(.top, 4)
            }
        }
        .padding(BoothifySpacing.xl)
        .frame(maxWidth: .infinity)
        .glassSurface(radius: BoothifyRadius.surface)
    }
}

// MARK: - AppLoadingState
struct AppLoadingState: View {
    var label: String = "Loading…"

    var body: some View {
        VStack(spacing: BoothifySpacing.sm) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(BoothifyTheme.violet)
            Text(label)
                .font(.caption)
                .foregroundStyle(BoothifyTheme.textMuted)
        }
        .padding(BoothifySpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - AppStatusPill
/// Coloured dot + label badge. Replaces one-off inline pill patterns.
struct AppStatusPill: View {
    let label: String
    var color: Color = BoothifyTheme.emerald
    var showDot: Bool = true

    var body: some View {
        HStack(spacing: 5) {
            if showDot {
                Circle().fill(color).frame(width: 6, height: 6)
            }
            Text(label)
                .font(.caption2.weight(.bold))
                .kerning(0.5)
        }
        .foregroundStyle(color)
        .padding(.horizontal, BoothifySpacing.sm)
        .padding(.vertical, 4)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.35), lineWidth: 0.8))
    }
}

// MARK: - AppListRow
/// Settings/options list row: icon badge + title/subtitle + accessory. Use in lists and option panels.
struct AppListRow: View {
    let symbol: String
    var symbolColor: Color = BoothifyTheme.violet
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    var badgeColor: Color = BoothifyTheme.violet
    var accessory: Accessory = .chevron
    var disabled: Bool = false
    let action: () -> Void

    enum Accessory {
        case chevron, external, none
        var icon: String? {
            switch self {
            case .chevron:  "chevron.right"
            case .external: "arrow.up.right.square"
            case .none:     nil
            }
        }
    }

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: BoothifySpacing.md) {
                AppIconBadge(symbol: symbol, color: symbolColor, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(disabled ? BoothifyTheme.textTertiary : .white)
                        if let badge {
                            Text(badge)
                                .font(.caption2.weight(.bold))
                                .kerning(0.4)
                                .foregroundStyle(badgeColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badgeColor.opacity(0.14), in: Capsule())
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }

                Spacer()

                if let icon = accessory.icon {
                    Image(systemName: icon)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(disabled ? "\(title), not available" : title)
    }
}

// MARK: - LaserCapsuleBorder
/// A bright violet "laser" segment orbiting a capsule's outline (hero CTAs).
/// Two layers — a blurred glow under a thin bright core — travel the border
/// on a seamless 2.6s loop. Reduce Motion degrades to a static violet rim.
struct LaserCapsuleBorder: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fraction of the outline lit at once.
    private let span: CGFloat = 0.28
    private let laserBright = Color(red: 0.78, green: 0.70, blue: 1.0)

    var body: some View {
        Group {
            if reduceMotion {
                Capsule()
                    .strokeBorder(BoothifyTheme.violet.opacity(0.55), lineWidth: 1.5)
            } else {
                ZStack {
                    segment(lineWidth: 5).blur(radius: 5)
                        .foregroundStyle(BoothifyTheme.violet)
                    segment(lineWidth: 1.8)
                        .foregroundStyle(laserBright)
                }
                .onAppear {
                    withAnimation(.linear(duration: 2.6).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The traveling arc, drawn in two trims so it wraps seamlessly past
    /// the path's start point.
    private func segment(lineWidth: CGFloat) -> some View {
        ZStack {
            Capsule()
                .trim(from: phase, to: min(phase + span, 1))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Capsule()
                .trim(from: 0, to: max(phase + span - 1, 0))
                .stroke(style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
    }
}

// MARK: - EntranceReveal
/// Staggered section entrance: fade + a 14pt rise, ordered so the hero
/// lands first and secondary blocks follow (~70ms apart). Re-arms on
/// disappear, so every return to a tab replays the sequence. Reduce
/// Motion shows content instantly.
struct EntranceReveal: ViewModifier {
    var order: Int = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 14)
            .onAppear {
                guard !shown, !reduceMotion else { return }
                withAnimation(.easeOut(duration: 0.38).delay(Double(order) * 0.07)) {
                    shown = true
                }
            }
            .onDisappear { shown = false }
    }
}

extension View {
    /// Staggered fade/rise entrance; `order` 0 = the screen's hero.
    func entrance(_ order: Int = 0) -> some View {
        modifier(EntranceReveal(order: order))
    }
}

// MARK: - GlassRowBackground
/// Glassmorphism background for `List` rows (settings detail screens):
/// dark material + the language's diagonal sheen. Pair with
/// `.scrollContentBackground(.hidden)` and `AtmosphericBackground` behind
/// the List. Reduce Transparency → solid elevated surface (sheen stays).
struct GlassRowBackground: View {
    var body: some View {
        ZStack {
            if UIAccessibility.isReduceTransparencyEnabled {
                BoothifyTheme.bgElevated
            } else {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            LinearGradient(
                colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

// MARK: - SettingsSectionCard
/// Glass section for settings screens: a quiet uppercase eyebrow floating
/// above a thin panel of rows. Layout-redesign primitive — settings screens
/// compose these on the atmosphere instead of rendering a generic iOS list.
struct SettingsSectionCard<Content: View>: View {
    var title: String? = nil
    /// When set, the card joins the screen's staggered entrance sequence.
    var entranceOrder: Int? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        if let entranceOrder {
            core.entrance(entranceOrder)
        } else {
            core
        }
    }

    private var core: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            if let title {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .kerning(1.2)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                    .padding(.leading, 4)
            }
            VStack(alignment: .leading, spacing: 0) { content() }
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.vertical, BoothifySpacing.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Faint violet under-tint so the pane reads as glass on the
                // black stage, not as a flat gray block.
                .background(
                    LinearGradient(
                        colors: [BoothifyTheme.indigoGlow.opacity(0.16), BoothifyTheme.violet.opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous)
                )
                .glassSurface(radius: BoothifyRadius.section)
        }
    }
}

// MARK: - AppDivider
struct AppDivider: View {
    var body: some View {
        Rectangle()
            .fill(BoothifyTheme.surfaceLine)
            .frame(maxWidth: .infinity)
            .frame(height: 0.5)
    }
}
