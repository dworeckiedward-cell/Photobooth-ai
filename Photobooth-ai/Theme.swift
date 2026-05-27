import SwiftUI

enum BoothifyTheme {
    static let bg          = Color(red: 0.04, green: 0.04, blue: 0.05)   // ~zinc-950
    static let surface1    = Color.white.opacity(0.05)
    static let surface2    = Color.white.opacity(0.08)
    static let surfaceLine = Color.white.opacity(0.10)

    static let textPrimary    = Color.white
    static let textSecondary  = Color(red: 0.65, green: 0.66, blue: 0.70)  // zinc-400
    static let textTertiary   = Color(red: 0.45, green: 0.46, blue: 0.50)  // zinc-500
    static let textMuted      = Color(red: 0.30, green: 0.31, blue: 0.35)  // zinc-600

    static let violet   = Color(red: 0.545, green: 0.361, blue: 0.965)    // violet-500
    static let fuchsia  = Color(red: 0.851, green: 0.275, blue: 0.937)    // fuchsia-500
    static let pink     = Color(red: 0.925, green: 0.282, blue: 0.6)
    static let emerald  = Color(red: 0.063, green: 0.725, blue: 0.506)
    static let amber    = Color(red: 0.960, green: 0.620, blue: 0.043)

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

// MARK: - Button styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                ZStack {
                    BoothifyTheme.primaryGradient
                    Color.white.opacity(configuration.isPressed ? 0.10 : 0)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: BoothifyTheme.violet.opacity(0.35), radius: 18, y: 8)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BoothifyTheme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(BoothifyTheme.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

// MARK: - Reusable surfaces

struct Surface: ViewModifier {
    var elevated: Bool = false
    func body(content: Content) -> some View {
        content
            .background(elevated ? BoothifyTheme.surface2 : BoothifyTheme.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    func boothifySurface(elevated: Bool = false) -> some View {
        modifier(Surface(elevated: elevated))
    }
}

// MARK: - Headings

struct GradientHeading: View {
    let text: String
    var font: Font = .system(.largeTitle, design: .default, weight: .bold)
    var body: some View {
        Text(text)
            .font(font)
            .kerning(-0.5)
            .foregroundStyle(BoothifyTheme.headingGradient)
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
