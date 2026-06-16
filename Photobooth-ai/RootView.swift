import SwiftUI

// MARK: - Tab definition

private enum BoothifyTab: Int, CaseIterable, Hashable {
    case home, events, settings

    var title: String {
        switch self {
        case .home:     "Booth"
        case .events:   "Events"
        case .settings: "Settings"
        }
    }

    /// Outline variant — shown when the tab is NOT selected (iOS convention).
    var icon: String {
        switch self {
        case .home:     "house"
        case .events:   "calendar"
        case .settings: "gearshape"
        }
    }

    /// Filled variant — shown when the tab IS selected (iOS convention).
    var selectedIcon: String {
        switch self {
        case .home:     "house.fill"
        case .events:   "calendar"
        case .settings: "gearshape.fill"
        }
    }
}

// MARK: - RootView

struct RootView: View {
    @Environment(AppState.self) private var app

    @State private var onboardingPresented: Bool = false
    @State private var selectedTab: BoothifyTab = .home
    @State private var profilePresented: Bool = false

    var body: some View {
        @Bindable var app = app
        Group {
            if app.isAuthLoading {
                AuthSplashView()
            } else if AppConfig.authGateEnabled && !app.isAuthenticated {
                LoginView()
            } else {
                mainApp(app: app)
            }
        }
    }

    @ViewBuilder
    private func mainApp(app: AppState) -> some View {
        @Bindable var app = app
        let atRoot = app.path.isEmpty

        ZStack(alignment: .bottom) {
            // Single NavigationStack — root swaps per selected tab,
            // deep nav (EventHub, Camera, etc.) uses app.path as always.
            NavigationStack(path: $app.path) {
                Group {
                    switch selectedTab {
                    case .home:     ModeSelectionView()
                    case .events:   EventsCalendarView()
                    case .settings: AppSettingsView()
                    }
                }
                .id(selectedTab)
                .transition(.opacity)
                .animation(.easeOut(duration: 0.18), value: selectedTab)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
            }
            .onChange(of: selectedTab) { _, _ in
                // Safety net: if somehow we're deep when tab changes, pop back.
                if !app.path.isEmpty { app.popToRoot() }
            }

            // ── Tab bar — only at root; slides in/out with deep navigation ──
            if atRoot {
                BoothifyTabBar(
                    selected: $selectedTab,
                    isProfileActive: profilePresented
                ) {
                    Haptics.tap(.light)
                    profilePresented = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Animation lives on the ZStack so the tab bar exit transition fires correctly.
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: atRoot)
        // Status HUD sits above everything, pointer-events off so it never blocks taps.
        .overlay(alignment: .top) {
            StatusOverlay().allowsHitTesting(false)
        }
        .sheet(isPresented: $onboardingPresented) {
            OnboardingQuizSheet { answers in applyOnboardingDefaults(answers) }
                .interactiveDismissDisabled(false)
        }
        .fullScreenCover(isPresented: $profilePresented) {
            ProfileCardView()
        }
        .task {
            if !OnboardingStore.hasCompleted {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                onboardingPresented = true
            }
        }
    }

    // MARK: - Onboarding defaults

    private func applyOnboardingDefaults(_ answers: OnboardingAnswers) {
        OnboardingStore.save(answers)
    }

    // MARK: - Navigation destinations (unchanged)

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .photoboothLanding:
            PhotoboothLandingView()
        case .eventHub(let id):
            EventHubView(eventId: id)
        case .camera(let id):
            CameraScreen(eventId: id)
                .toolbar(.hidden, for: .navigationBar)
        case .stylePicker(let eventId, let imageData):
            StylePickerView(eventId: eventId, capturedImageData: imageData)
        case .result(let eventId, let photoId):
            ResultView(eventId: eventId, photoId: photoId)
        case .gallery(let id):
            GalleryView(eventId: id)
        case .slideshow(let id):
            SlideshowView(eventId: id)
                .toolbar(.hidden, for: .navigationBar)

        case .settingsHub(let id):
            SettingsHubView(eventId: id)
        case .settingsCapture(let id):
            CaptureSettingsView(eventId: id)
        case .settingsCamera(let id):
            CameraSettingsView(eventId: id)
        case .settingsAIPortraits(let id):
            AIPortraitsSettingsView(eventId: id)
        case .settingsAI360(let id):
            AI360SettingsView(eventId: id)
        case .settingsEffects(let id):
            EffectsSettingsView(eventId: id)
        case .settingsSharing(let id):
            SharingSettingsView(eventId: id)
        case .settingsEmailSMS(let id):
            EmailSMSSettingsView(eventId: id)
        case .settingsLockPin(let id):
            LockPinSettingsView(eventId: id)
        case .settingsGallerySlideshow(let id):
            GallerySlideshowSettingsView(eventId: id)
        case .settingsPrint(let id):
            PrintSetupSettingsView(eventId: id)
        case .settingsBackgroundRemoval(let id):
            BackgroundRemovalSettingsView(eventId: id)
        case .settingsStickers(let id):
            BrandOverlaySettingsView(eventId: id)
        case .settingsVirtualAttendant(let id):
            VirtualAttendantSettingsView(eventId: id)
        case .settingsDisclaimer(let id):
            DisclaimerSettingsView(eventId: id)
        case .settingsSurvey(let id):
            SurveySettingsView(eventId: id)
        case .settingsSharingStatus(let id):
            SharingStatusView(eventId: id)
        case .settingsAccount(let id):
            AccountSettingsView(eventId: id)
        case .settingsComingSoon(let title, let blurb):
            ComingSoonView(title: title, blurb: blurb)
        case .aboutBoothify:
            AboutBoothifyView()

        case .booth360Landing:
            Booth360LandingView()
        case .booth360EventHub(let id):
            Booth360EventHubView(eventId: id)
        case .booth360Recording(let id):
            Booth360RecordingView(eventId: id)
                .toolbar(.hidden, for: .navigationBar)
        case .booth360Processing(let id):
            Booth360ProcessingView(jobId: id)
        case .booth360Result(let id):
            Booth360ResultView(jobId: id)
        case .settings360Hub(let id):
            SettingsHubView(eventId: id, mode: .ai360)
        }
    }
}

// MARK: - Custom tab bar

private struct BoothifyTabBar: View {
    @Binding var selected: BoothifyTab
    var isProfileActive: Bool = false
    let onProfileTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // @ScaledMetric: these sizes track the user's Dynamic Type setting
    @ScaledMetric(relativeTo: .caption2) private var tabIconSize: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var tabLabelSize: CGFloat = 10

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?
            .windows.first(where: { $0.isKeyWindow })?
            .safeAreaInsets.bottom) ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            // Native hairline top separator — a single thin line, like UITabBar
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            HStack(alignment: .top, spacing: 0) {
                ForEach(BoothifyTab.allCases, id: \.rawValue) { tab in
                    navTabButton(tab)
                }
                profileTabButton
            }
            .padding(.top, 8)
            .padding(.bottom, max(safeAreaBottom, 10))
        }
        .background(.ultraThinMaterial)
        .ignoresSafeArea(edges: .bottom)
    }

    @ViewBuilder
    private func navTabButton(_ tab: BoothifyTab) -> some View {
        let isActive = selected == tab
        Button {
            guard selected != tab else { return }
            Haptics.tap(.light)
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                selected = tab
            }
        } label: {
            tabItem(icon: tab.icon, selectedIcon: tab.selectedIcon, title: tab.title, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var profileTabButton: some View {
        Button(action: onProfileTap) {
            tabItem(icon: "person", selectedIcon: "person.fill", title: "Profile", isActive: isProfileActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
        .accessibilityHint("Opens your profile card")
        .accessibilityAddTraits(isProfileActive ? [.isSelected] : [])
    }

    @ViewBuilder
    private func tabItem(icon: String, selectedIcon: String, title: String, isActive: Bool) -> some View {
        let tint = isActive ? BoothifyTheme.violet : BoothifyTheme.textMuted
        VStack(spacing: 4) {
            Image(systemName: isActive ? selectedIcon : icon)
                .font(.system(size: tabIconSize))
                .symbolRenderingMode(.hierarchical)
                .frame(height: tabIconSize + 4)
                // Subtle native bounce on selection. Passing a constant when
                // reduce-motion is on means the value never changes → no animation.
                .symbolEffect(.bounce, value: reduceMotion ? false : isActive)

            Text(title)
                .font(.system(size: tabLabelSize, weight: isActive ? .semibold : .medium))
                .lineLimit(1)
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isActive)
    }
}

// MARK: - App Settings tab

private struct AppSettingsView: View {
    @Environment(AppState.self) private var app
    @State private var confirmSignOut = false

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            List {
                // ── App ──
                Section("App") {
                    NavigationLink(destination: AboutBoothifyView()) {
                        Label("About Boothify", systemImage: "info.circle")
                            .foregroundStyle(.white)
                    }
                }
                .listRowBackground(BoothifyTheme.surface1)

                // ── Account ──
                Section {
                    Button(role: .destructive) {
                        Haptics.tap(.medium)
                        confirmSignOut = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } header: {
                    Text("Account")
                } footer: {
                    Text("Boothify \(appVersion)")
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, BoothifySpacing.lg)
                }
                .listRowBackground(BoothifyTheme.surface1)
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Sign out of Boothify?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Profile card (sheet)

private struct ProfileCardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @ScaledMetric(relativeTo: .title)  private var avatarInitialsSize: CGFloat = 34
    @ScaledMetric(relativeTo: .title2) private var statNumberSize: CGFloat = 30

    private var displayName: String { app.currentUser?.fullName ?? "Operator" }
    private var email: String?      { app.currentUser?.email }
    private var totalPhotos: Int    { app.events.map(\.completedPhotos).reduce(0, +) }

    private var initials: String {
        displayName
            .components(separatedBy: " ")
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
            .joined()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BoothifyTheme.bg.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        statsRow
                            .padding(.top, BoothifySpacing.lg)
                            .padding(.horizontal, BoothifySpacing.lg)
                        settingsHint
                            .padding(.top, BoothifySpacing.lg)
                            .padding(.horizontal, BoothifySpacing.lg)
                            .padding(.bottom, BoothifySpacing.xl)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.tap(.light)
                        dismiss()
                    }
                    .foregroundStyle(BoothifyTheme.violet)
                    .font(.body.weight(.semibold))
                }
            }
        }
    }

    // Quiet signpost — account actions (About, Sign Out) live in the Settings tab.
    private var settingsHint: some View {
        HStack(spacing: BoothifySpacing.xs) {
            Image(systemName: "gearshape")
                .font(.caption)
            Text("App info and sign out are in the Settings tab.")
                .font(.caption)
        }
        .foregroundStyle(BoothifyTheme.textTertiary)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Header with gradient + avatar

    private var header: some View {
        ZStack(alignment: .bottom) {
            // Base gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: BoothifyTheme.violet.opacity(0.60), location: 0),
                            .init(color: Color(red: 0.22, green: 0.10, blue: 0.45).opacity(0.70), location: 0.45),
                            .init(color: BoothifyTheme.bg, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 220)

            // Ambient radial bloom at top-center (matches LoginView)
            RadialGradient(
                colors: [BoothifyTheme.violet.opacity(0.35), .clear],
                center: .init(x: 0.5, y: 0.0),
                startRadius: 0,
                endRadius: 260
            )
            .frame(height: 220)
            .allowsHitTesting(false)

            // Noise texture for premium feel
            Rectangle()
                .fill(.white.opacity(0.025))
                .frame(height: 220)
                .blendMode(.overlay)
                .allowsHitTesting(false)

            // Avatar — overlaps gradient bottom edge
            VStack(spacing: BoothifySpacing.md) {
                ZStack {
                    // Outer diffuse bloom — dimensional layering
                    Circle()
                        .fill(BoothifyTheme.violet.opacity(0.30))
                        .frame(width: 120, height: 120)
                        .blur(radius: 20)

                    // Inner ambient ring
                    Circle()
                        .fill(BoothifyTheme.violet.opacity(0.10))
                        .frame(width: 106, height: 106)

                    // Avatar fill
                    Circle()
                        .fill(Color(red: 0.10, green: 0.07, blue: 0.18))
                        .frame(width: 96, height: 96)
                        .shadow(color: BoothifyTheme.violet.opacity(0.55), radius: 24, y: 8)

                    // Gradient stroke border
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    BoothifyTheme.violet,
                                    BoothifyTheme.violet.opacity(0.20)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 96, height: 96)

                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: avatarInitialsSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.30), radius: 4, y: 2)
                    if let email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                    }
                }
                .padding(.bottom, BoothifySpacing.lg)
            }
            .offset(y: 60)
        }
        .padding(.bottom, 60)
    }

    // MARK: - Stats row

    private var statsRow: some View {
        HStack(spacing: BoothifySpacing.sm) {
            profileStat(value: "\(app.events.count)", label: "Events", tint: BoothifyTheme.violet)
            profileStat(value: "\(totalPhotos)", label: "Photos", tint: BoothifyTheme.emerald)
        }
    }

    private func profileStat(value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: statNumberSize, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BoothifyTheme.textSecondary)
            // Colored accent bar — visual hierarchy cue per stat
            Rectangle()
                .fill(tint.opacity(0.60))
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, BoothifySpacing.xl)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BoothifySpacing.lg)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        )
    }

}

// MARK: - Auth splash

private struct AuthSplashView: View {
    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            ProgressView()
                .tint(BoothifyTheme.violet)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
