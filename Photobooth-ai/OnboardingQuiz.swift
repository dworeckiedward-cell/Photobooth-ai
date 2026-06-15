import SwiftUI

/// IM3: lightweight first-login onboarding. Surfaces ONCE per device per Apple
/// ID (gate flag in `UserDefaults`). Captures a couple of operator-facing
/// preferences that meaningfully change defaults later — primary mode,
/// preferred 360 template, default branding — so the rest of the app feels
/// pre-tuned to their event type instead of generic.
///
/// Skippable at every step. Preferences only persist locally; no required
/// backend (sync hooks left for the future, see TODO-HUMAN.md → IM3 sync).

// MARK: - Model

enum EventCategory: String, Codable, CaseIterable, Identifiable {
    case wedding, corporate, birthday, club, other
    var id: String { rawValue }
    var label: String {
        switch self {
        case .wedding: "Weddings"
        case .corporate: "Corporate"
        case .birthday: "Birthdays"
        case .club: "Clubs & nightlife"
        case .other: "Other"
        }
    }
    var symbol: String {
        switch self {
        case .wedding: "heart.fill"
        case .corporate: "briefcase.fill"
        case .birthday: "birthday.cake.fill"
        case .club: "music.note"
        case .other: "sparkles"
        }
    }
}

enum PrimaryBoothMode: String, Codable, CaseIterable, Identifiable {
    case aiPhotobooth, ai360, both
    var id: String { rawValue }
    var label: String {
        switch self {
        case .aiPhotobooth: "AI Photobooth"
        case .ai360: "360 AI Booth"
        case .both: "Both"
        }
    }
    var symbol: String {
        switch self {
        case .aiPhotobooth: "camera.aperture"
        case .ai360: "video.fill"
        case .both: "rectangle.stack.fill"
        }
    }
}

enum BrandingPreference: String, Codable, CaseIterable, Identifiable {
    case clientLogo, eventName, none
    var id: String { rawValue }
    var label: String {
        switch self {
        case .clientLogo: "Client logo on every result"
        case .eventName: "Event name watermark"
        case .none: "No branding for now"
        }
    }
    var symbol: String {
        switch self {
        case .clientLogo: "rosette"
        case .eventName: "textformat"
        case .none: "minus.circle"
        }
    }
}

struct OnboardingAnswers: Codable {
    var category: EventCategory? = nil
    var primaryMode: PrimaryBoothMode? = nil
    var branding: BrandingPreference? = nil
    var preferredTemplateRawDuration: Double? = nil
}

// MARK: - Persistence

enum OnboardingStore {
    private static let completedKey = "boothify.onboarding.completed"
    private static let answersKey = "boothify.onboarding.answers"

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: completedKey)
    }

    static func markCompleted() {
        UserDefaults.standard.set(true, forKey: completedKey)
    }

    /// Test hook — call from Settings → Reset if we ever ship that.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: completedKey)
        UserDefaults.standard.removeObject(forKey: answersKey)
    }

    static var lastAnswers: OnboardingAnswers? {
        guard let data = UserDefaults.standard.data(forKey: answersKey) else { return nil }
        return try? JSONDecoder().decode(OnboardingAnswers.self, from: data)
    }

    static func save(_ answers: OnboardingAnswers) {
        if let data = try? JSONEncoder().encode(answers) {
            UserDefaults.standard.set(data, forKey: answersKey)
        }
    }
}

// MARK: - Quiz sheet

struct OnboardingQuizSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Int = 0
    @State private var answers = OnboardingAnswers()
    /// Tracks swipe direction so the transition slides the right way.
    @State private var goingForward: Bool = true
    /// Cancelled and restarted whenever the user changes their selection.
    @State private var autoAdvanceTask: Task<Void, Never>? = nil

    /// Called after either Finish or Skip so the host (RootView) can apply
    /// the answers to defaults and flip the persistent completion flag.
    let onFinish: (OnboardingAnswers) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                BoothifyTheme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    progressBar
                        .padding(.horizontal, BoothifySpacing.lg)
                        .padding(.top, BoothifySpacing.md)

                    Text(step < totalSteps ? "Step \(step + 1) of \(totalSteps)" : "Done")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85), value: step)
                        .padding(.top, BoothifySpacing.sm)

                    // Step content — .id(step) forces SwiftUI to swap views so
                    // the asymmetric transition fires on every step change.
                    ZStack {
                        Group {
                            switch step {
                            case 0: categoryStep
                            case 1: modeStep
                            case 2: brandingStep
                            case 3: templateStep
                            default: summaryStep
                            }
                        }
                        .id(step)
                        .transition(stepTransition)
                    }
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, BoothifySpacing.lg)
                    .padding(.top, BoothifySpacing.lg)

                    bottomBar
                        .padding(.horizontal, BoothifySpacing.lg)
                        .padding(.bottom, step == totalSteps ? BoothifySpacing.lg : 0)
                        .padding(.top, step == totalSteps ? BoothifySpacing.md : 0)
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if step < totalSteps {
                        Button("Skip") {
                            autoAdvanceTask?.cancel()
                            finish(saving: false)
                        }
                        .foregroundStyle(BoothifyTheme.textSecondary)
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    private var totalSteps: Int { 4 }

    // Directional slide + fade: forward → slides from trailing, back → from leading.
    private var stepTransition: AnyTransition {
        let insertOffset: CGFloat = goingForward ? 36 : -36
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: insertOffset, y: 0)),
            removal:   .opacity.combined(with: .offset(x: -insertOffset, y: 0))
        )
    }

    private var stepAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.86)
    }

    // MARK: - Auto-advance

    /// Schedule a forward step after a short pause so the selected state is visible.
    /// Cancels any pending advance first — safe to call on every tap.
    private func scheduleAutoAdvance() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.26))
            guard !Task.isCancelled else { return }
            advance()
        }
    }

    private func advance() {
        guard step < totalSteps else { return }
        goingForward = true
        Haptics.tap(.light)
        withAnimation(stepAnimation) { step += 1 }
    }

    private func goBack() {
        guard step > 0 else { return }
        autoAdvanceTask?.cancel()
        goingForward = false
        Haptics.tap(.light)
        withAnimation(stepAnimation) { step -= 1 }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BoothifyTheme.surface2)
                    .frame(height: 4)
                Capsule()
                    .fill(BoothifyTheme.violet)
                    .frame(width: geo.size.width * CGFloat(min(step + 1, totalSteps)) / CGFloat(totalSteps), height: 4)
                    .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: step)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Steps

    @ViewBuilder
    private var categoryStep: some View {
        VStack(spacing: BoothifySpacing.lg) {
            stepHeader(
                title: "What events do you run?",
                subtitle: "We'll preload styles + branding that fit."
            )
            optionGrid(
                options: EventCategory.allCases,
                selected: answers.category
            ) {
                answers.category = $0
                scheduleAutoAdvance()
            }
        }
    }

    @ViewBuilder
    private var modeStep: some View {
        VStack(spacing: BoothifySpacing.lg) {
            stepHeader(
                title: "Primary booth mode?",
                subtitle: "Sets your default after Sign In."
            )
            optionList(
                options: PrimaryBoothMode.allCases,
                selected: answers.primaryMode
            ) {
                answers.primaryMode = $0
                scheduleAutoAdvance()
            }
        }
    }

    @ViewBuilder
    private var brandingStep: some View {
        VStack(spacing: BoothifySpacing.lg) {
            stepHeader(
                title: "Branding on every result?",
                subtitle: "You can always change this per event."
            )
            optionList(
                options: BrandingPreference.allCases,
                selected: answers.branding
            ) {
                answers.branding = $0
                scheduleAutoAdvance()
            }
        }
    }

    @ViewBuilder
    private var templateStep: some View {
        VStack(spacing: BoothifySpacing.lg) {
            stepHeader(
                title: "Default 360 montage length?",
                subtitle: "Drives the recording duration + speed ramp."
            )
            VStack(spacing: BoothifySpacing.sm) {
                templateChoice(label: "Quick · 4s", raw: 4)
                templateChoice(label: "Standard · 9s", badge: "Recommended", raw: 9)
                templateChoice(label: "Epic · 15s", raw: 15)
            }
        }
    }

    @ViewBuilder
    private var summaryStep: some View {
        VStack(spacing: BoothifySpacing.md) {
            ZStack {
                Circle()
                    .fill(BoothifyTheme.emerald.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(BoothifyTheme.emerald)
                    .symbolEffect(.bounce, options: .nonRepeating)
            }
            VStack(spacing: BoothifySpacing.xs) {
                Text("All set.")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("You can change everything in Settings later.")
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: BoothifySpacing.xs) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private func optionGrid<O: Identifiable & Equatable>(
        options: [O],
        selected: O?,
        labelFor: ((O) -> String)? = nil,
        symbolFor: ((O) -> String)? = nil,
        choose: @escaping (O) -> Void
    ) -> some View where O: CaseIterable {
        let columns = [GridItem(.flexible(), spacing: BoothifySpacing.sm), GridItem(.flexible(), spacing: BoothifySpacing.sm)]
        LazyVGrid(columns: columns, spacing: BoothifySpacing.sm) {
            ForEach(options) { option in
                let (label, symbol) = labelAndSymbol(for: option, labelFor: labelFor, symbolFor: symbolFor)
                optionCard(label: label, symbol: symbol, isSelected: selected == option) {
                    Haptics.selection()
                    choose(option)
                }
            }
        }
    }

    @ViewBuilder
    private func optionList<O: Identifiable & Equatable>(
        options: [O],
        selected: O?,
        labelFor: ((O) -> String)? = nil,
        symbolFor: ((O) -> String)? = nil,
        choose: @escaping (O) -> Void
    ) -> some View {
        VStack(spacing: BoothifySpacing.sm) {
            ForEach(options) { option in
                let (label, symbol) = labelAndSymbol(for: option, labelFor: labelFor, symbolFor: symbolFor)
                optionCard(label: label, symbol: symbol, isSelected: selected == option, wide: true) {
                    Haptics.selection()
                    choose(option)
                }
            }
        }
    }

    private func labelAndSymbol<O>(
        for option: O,
        labelFor: ((O) -> String)?,
        symbolFor: ((O) -> String)?
    ) -> (String, String) {
        if let labelFor, let symbolFor {
            return (labelFor(option), symbolFor(option))
        }
        if let opt = option as? EventCategory { return (opt.label, opt.symbol) }
        if let opt = option as? PrimaryBoothMode { return (opt.label, opt.symbol) }
        if let opt = option as? BrandingPreference { return (opt.label, opt.symbol) }
        return ("\(option)", "square.dashed")
    }

    @ViewBuilder
    private func optionCard(label: String, symbol: String, isSelected: Bool, wide: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BoothifySpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous)
                        .fill(isSelected ? BoothifyTheme.violet.opacity(0.20) : BoothifyTheme.surface2)
                        .frame(width: 32, height: 32)
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
                    Image(systemName: symbol)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSelected ? BoothifyTheme.violet : BoothifyTheme.textSecondary)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelected)
                }
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                if wide { Spacer() }
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(BoothifyTheme.violet)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.sm + 4)
            .frame(maxWidth: .infinity, alignment: wide ? .leading : .center)
            .background(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .fill(isSelected ? BoothifyTheme.violet.opacity(0.10) : BoothifyTheme.surface1)
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isSelected)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .stroke(isSelected ? BoothifyTheme.violet : BoothifyTheme.surfaceLine, lineWidth: isSelected ? 1.5 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSelected)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func templateChoice(label: String, badge: String? = nil, raw: Double) -> some View {
        let isSel = answers.preferredTemplateRawDuration == raw
        Button {
            Haptics.selection()
            answers.preferredTemplateRawDuration = raw
            scheduleAutoAdvance()
        } label: {
            HStack(spacing: BoothifySpacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous)
                        .fill(isSel ? BoothifyTheme.violet.opacity(0.20) : BoothifyTheme.surface2)
                        .frame(width: 32, height: 32)
                        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isSel)
                    Image(systemName: "slowmo")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isSel ? BoothifyTheme.violet : BoothifyTheme.textSecondary)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSel)
                }
                Text(label)
                    .foregroundStyle(.white)
                    .font(.subheadline.weight(.medium))
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.violet)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BoothifyTheme.violet.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer()
                if isSel {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(BoothifyTheme.violet)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.sm + 4)
            .background(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .fill(isSel ? BoothifyTheme.violet.opacity(0.10) : BoothifyTheme.surface1)
                    .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.72), value: isSel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .stroke(isSel ? BoothifyTheme.violet : BoothifyTheme.surfaceLine, lineWidth: isSel ? 1.5 : 1)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isSel)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if step == totalSteps {
            // Summary screen only — primary Finish button
            Button {
                Haptics.tap()
                finish(saving: true)
            } label: {
                HStack(spacing: BoothifySpacing.xs) {
                    Text("Finish")
                    Image(systemName: "checkmark")
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(minHeight: 44)
        }
        // Question steps: no bottom button — tap answer to auto-advance, Skip in toolbar
    }

    private func finish(saving: Bool) {
        if saving {
            OnboardingStore.save(answers)
        }
        OnboardingStore.markCompleted()
        onFinish(answers)
        dismiss()
    }
}

#Preview {
    OnboardingQuizSheet { _ in }
}
