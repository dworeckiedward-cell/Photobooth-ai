import SwiftUI

// MARK: - Tab definition

private enum BoothifyTab: Int, CaseIterable, Hashable {
    case home, events, settings

    var title: String {
        switch self {
        case .home:     "Home"
        case .events:   "Events"
        case .settings: "Settings"
        }
    }

    var icon: String {
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
                BoothifyTabBar(selected: $selectedTab) {
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
        .sheet(isPresented: $profilePresented) {
            ProfileCardView()
        }
        .task {
            if !OnboardingStore.hasCompleted {
                try? await Task.sleep(for: .milliseconds(350))
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
    let onProfileTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var safeAreaBottom: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first?.safeAreaInsets.bottom ?? 0
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(BoothifyTheme.surfaceLine)
                .frame(height: 0.5)

            HStack(spacing: 0) {
                ForEach(BoothifyTab.allCases, id: \.rawValue) { tab in
                    navTabButton(tab)
                }
                profileTabButton
            }
            .padding(.top, 10)
            .padding(.bottom, max(safeAreaBottom, 12))
        }
        .background(
            Color(red: 0.07, green: 0.07, blue: 0.09)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    @ViewBuilder
    private func navTabButton(_ tab: BoothifyTab) -> some View {
        let isActive = selected == tab
        Button {
            guard selected != tab else { return }
            Haptics.tap(.light)
            withAnimation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.72)) {
                selected = tab
            }
        } label: {
            tabLabel(icon: tab.icon, title: tab.title, isActive: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }

    private var profileTabButton: some View {
        Button(action: onProfileTap) {
            tabLabel(icon: "person.fill", title: "Profile", isActive: false)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Profile")
    }

    @ViewBuilder
    private func tabLabel(icon: String, title: String, isActive: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 21, weight: isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? BoothifyTheme.violet : BoothifyTheme.textMuted)
                .scaleEffect(isActive ? 1.08 : 1.0)
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.70), value: isActive)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isActive ? BoothifyTheme.violet : BoothifyTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - App Settings tab

private struct AppSettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            List {
                Section("App") {
                    NavigationLink {
                        AboutBoothifyView()
                    } label: {
                        Label("About Boothify", systemImage: "info.circle")
                            .foregroundStyle(.white)
                    }
                }

                Section("Account") {
                    Button(role: .destructive) {
                        Haptics.tap(.medium)
                        app.signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Profile card (sheet)

private struct ProfileCardView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var confirmSignOut = false

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
                        optionsList
                            .padding(.top, BoothifySpacing.lg)
                            .padding(.horizontal, BoothifySpacing.lg)
                        signOutButton
                            .padding(.top, BoothifySpacing.xl)
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
            .confirmationDialog("Sign out of Boothify?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { app.signOut() }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Header with gradient + avatar

    private var header: some View {
        ZStack(alignment: .bottom) {
            // Gradient background
            Rectangle()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: BoothifyTheme.violet.opacity(0.55), location: 0),
                            .init(color: Color(red: 0.22, green: 0.10, blue: 0.45).opacity(0.65), location: 0.5),
                            .init(color: BoothifyTheme.bg, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 200)

            // Subtle noise/grain overlay for texture
            Rectangle()
                .fill(.white.opacity(0.03))
                .frame(height: 200)
                .blendMode(.overlay)

            // Avatar — overlaps the gradient bottom edge
            VStack(spacing: BoothifySpacing.md) {
                ZStack {
                    // Glow ring
                    Circle()
                        .fill(BoothifyTheme.violet.opacity(0.25))
                        .frame(width: 108, height: 108)
                        .blur(radius: 14)

                    Circle()
                        .fill(Color(red: 0.10, green: 0.07, blue: 0.18))
                        .frame(width: 96, height: 96)

                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [BoothifyTheme.violet, BoothifyTheme.violet.opacity(0.30)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                        .frame(width: 96, height: 96)

                    Text(initials.isEmpty ? "?" : initials)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 4) {
                    Text(displayName)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    if let email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.55))
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
            statCard(value: "\(app.events.count)", label: "Events", icon: "calendar")
            statCard(value: "\(totalPhotos)", label: "Photos", icon: "photo.on.rectangle")
        }
    }

    @ViewBuilder
    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: BoothifySpacing.xs) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(BoothifyTheme.violet)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(BoothifyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BoothifySpacing.md)
        .background(BoothifyTheme.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
    }

    // MARK: - Options list

    private var optionsList: some View {
        VStack(spacing: 1) {
            optionRow(icon: "info.circle.fill", iconColor: Color(red: 0.30, green: 0.55, blue: 0.98),
                      title: "About Boothify") {
                // NavigationLink handled below
            }
            .overlay {
                NavigationLink {
                    AboutBoothifyView()
                } label: {
                    Color.clear
                }
            }

            optionRow(icon: "bell.fill", iconColor: BoothifyTheme.amber,
                      title: "Notifications", badge: "Coming soon") {}

            optionRow(icon: "shield.fill", iconColor: BoothifyTheme.emerald,
                      title: "Privacy & Security", badge: "Coming soon") {}
        }
        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func optionRow(icon: String, iconColor: Color, title: String, badge: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: BoothifySpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(iconColor)
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                Spacer()
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(BoothifyTheme.surface2)
                        .clipShape(Capsule())
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textMuted)
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.sm + 2)
            .background(BoothifyTheme.surface1)
        }
        .buttonStyle(.plain)
        .disabled(badge != nil)
    }

    // MARK: - Sign out

    private var signOutButton: some View {
        Button {
            Haptics.tap(.medium)
            confirmSignOut = true
        } label: {
            HStack(spacing: BoothifySpacing.sm) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                Text("Sign Out")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(BoothifyTheme.error)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(BoothifyTheme.error.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .stroke(BoothifyTheme.error.opacity(0.22), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        }
        .buttonStyle(.plain)
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
