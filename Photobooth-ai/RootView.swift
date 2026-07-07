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

    @State private var selectedTab: BoothifyTab = .home
    @State private var store = StoreManager()

    var body: some View {
        @Bindable var app = app
        Group {
            if app.isAuthLoading {
                AuthSplashView()
            } else if (AppConfig.authGateEnabled || app.didSignOut) && !app.isAuthenticated {
                // didSignOut: debug builds skip the gate, but an EXPLICIT
                // sign-out must still visibly land on the login screen.
                LoginView()
            } else {
                mainApp(app: app)
            }
        }
        .environment(store)
        .task { await store.load() }
    }

    @ViewBuilder
    private func mainApp(app: AppState) -> some View {
        @Bindable var app = app
        let atRoot = app.path.isEmpty

        // Single NavigationStack — root swaps per selected tab,
        // deep nav (EventHub, Camera, etc.) uses app.path as always.
        NavigationStack(path: $app.path) {
            ZStack {
                AtmosphericBackground()
            Group {
                if app.isKiosk, let kioskId = app.kioskEventId {
                    // Kiosk root — branded attract screen, no tabs. The guest
                    // capture flow pushes onto app.path as usual; on completion it
                    // pops back here.
                    KioskAttractView(eventId: kioskId)
                } else {
                    switch selectedTab {
                    case .home:     Booth360LandingView()
                    case .events:   EventsCalendarView()
                    case .settings: AppSettingsView()
                    }
                }
            }
            .id(app.isKiosk ? "kiosk" : "tab-\(selectedTab.rawValue)")
            // Reserve room at the bottom of the root tab screens so scroll/list
            // content (e.g. "Notifications", "New Event") never hides behind the
            // floating tab bar. Pushed destinations don't inherit this.
            .safeAreaPadding(.bottom, (atRoot && !app.isKiosk) ? 118 : 0)
            .transition(.opacity)
            .animation(.easeOut(duration: 0.18), value: selectedTab)
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
            }
        }
        .onChange(of: selectedTab) { _, _ in
            // Safety net: if somehow we're deep when tab changes, pop back.
            if !app.path.isEmpty { app.popToRoot() }
        }
        // ── Floating tab bar — anchored to the bottom edge via overlay so it
        // sits low like Apple's floating controls. Content clearance is handled
        // separately by safeAreaPadding above (we do NOT use safeAreaInset for
        // positioning, which would push the bar too high).
        .overlay(alignment: .bottom) {
            if atRoot && !app.isKiosk {
                BoothifyTabBar(selected: $selectedTab)
                    .padding(.horizontal, 24)
                    // Negative bottom padding pulls the pill down toward the
                    // physical edge (overlay otherwise pins it above the ~34pt
                    // home-indicator safe area, which read as "too high" on
                    // iPhone 17). Lands it ~14pt above the bottom edge.
                    .padding(.bottom, -18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        // Animation drives the tab bar slide-in/out with deep navigation.
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: atRoot)
        // Status HUD sits above everything, pointer-events off so it never blocks taps.
        .overlay(alignment: .top) {
            StatusOverlay().allowsHitTesting(false)
        }
    }

    // MARK: - Navigation destinations (unchanged)

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {

        case .settingsCamera(let id):
            CameraSettingsView(eventId: id)
        case .settingsAI360(let id):
            AI360SettingsView(eventId: id)
        case .settingsSharing(let id):
            SharingSettingsView(eventId: id)
        case .settingsEmailSMS(let id):
            EmailSMSSettingsView(eventId: id)
        case .settingsLockPin(let id):
            LockPinSettingsView(eventId: id)
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // @ScaledMetric: these sizes track the user's Dynamic Type setting
    @ScaledMetric(relativeTo: .caption2) private var inactiveIcon: CGFloat = 26
    @ScaledMetric(relativeTo: .caption2) private var activeIcon: CGFloat = 30
    @ScaledMetric(relativeTo: .caption2) private var tabLabelSize: CGFloat = 11

    private let corner: CGFloat = 28

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ForEach(BoothifyTab.allCases, id: \.rawValue) { tab in
                navTabButton(tab)
            }
        }
        .padding(.horizontal, BoothifySpacing.sm)
        .padding(.vertical, BoothifySpacing.sm)
        .background(barMaterial)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay(
            // Faint top-weighted stroke — the liquid-glass rim highlight.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.20), Color.white.opacity(0.04)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
        // Outer margins (horizontal + bottom lift) are applied by the overlay
        // in RootView so the bar anchors low against the device bottom edge.
    }

    /// Dark translucent liquid glass — ultraThinMaterial forced to a dark
    /// scheme so blur reads premium-dark, plus a subtle violet floor wash.
    private var barMaterial: some View {
        RoundedRectangle(cornerRadius: corner, style: .continuous)
            .fill(.ultraThinMaterial)
            .environment(\.colorScheme, .dark)
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                LinearGradient(
                    colors: [BoothifyTheme.violet.opacity(0.10), .clear],
                    startPoint: .bottom, endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            )
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

    @ViewBuilder
    private func tabItem(icon: String, selectedIcon: String, title: String, isActive: Bool) -> some View {
        // Atmospheric Glass: compact icon-only pill (reference style). The
        // title lives on as the accessibility label; the active tab sits in a
        // soft glass "seat" instead of relying on a text label.
        Image(systemName: isActive ? selectedIcon : icon)
            .font(.system(size: inactiveIcon, weight: .regular))
            .symbolRenderingMode(.hierarchical)
            .symbolEffect(.bounce, value: reduceMotion ? false : isActive)
            .foregroundStyle(isActive ? .white : BoothifyTheme.textMuted)
            .frame(width: 52, height: 44) // 44pt+ tap target (HIG)
            .background {
                if isActive {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                }
            }
            .contentShape(Rectangle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isActive)
    }
}

// MARK: - App Settings tab

private struct AppSettingsView: View {
    @Environment(AppState.self) private var app
    @Environment(StoreManager.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var confirmSignOut = false
    @State private var paywallPresented = false

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    private var displayName: String { app.currentUser?.fullName ?? "Operator" }
    private var email: String { app.currentUser?.email ?? "—" }

    var body: some View {
        // Layout redesign: designed settings on the shared atmosphere (which
        // RootView already paints underneath) — floating glass sections and
        // amber icons instead of a generic black inset-grouped list.
        ScrollView {
            VStack(alignment: .leading, spacing: BoothifySpacing.lg) {
                // ── Profile header (pushes the full profile) ─────────────
                NavigationLink {
                    ProfileCardView()
                } label: {
                    HStack(spacing: BoothifySpacing.md) {
                        ZStack {
                            Circle()
                                .fill(BoothifyTheme.violet.opacity(0.16))
                                .frame(width: 56, height: 56)
                            Text(String(displayName.prefix(1)))
                                .font(.title2.weight(.bold))
                                .foregroundStyle(BoothifyTheme.violet)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(displayName)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("View profile")
                                .font(.subheadline)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(BoothifyTheme.textMuted)
                    }
                    .padding(BoothifySpacing.md)
                    // Rich glass — violet-lit pane, language-consistent.
                    .background(
                        LinearGradient(
                            colors: [BoothifyTheme.indigoGlow.opacity(0.26), BoothifyTheme.violet.opacity(0.07)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous)
                    )
                    .glassSurface(radius: BoothifyRadius.section)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Profile, \(displayName)")
                .accessibilityHint("Opens your profile")
                .entrance(0)

                // ── Account & Plan ───────────────────────────────────────
                SettingsSectionCard(title: "Account & Plan", entranceOrder: 1) {
                    // Subscription tier — reflects the real StoreKit entitlement,
                    // not a hardcoded badge. Tapping opens the paywall.
                    Button {
                        Haptics.tap(.light)
                        paywallPresented = true
                    } label: {
                        HStack {
                            Label("Subscription", systemImage: "sparkle")
                                .foregroundStyle(.white)
                            Spacer()
                            let isPaid = store.currentTier != .free
                            HStack(spacing: 4) {
                                if isPaid {
                                    Image(systemName: "crown.fill")
                                        .font(.caption2.weight(.bold))
                                }
                                Text(store.currentTier.displayName.uppercased())
                                    .font(.caption.weight(.bold))
                                    .kerning(0.4)
                            }
                            .foregroundStyle(isPaid ? BoothifyTheme.violet : BoothifyTheme.textSecondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background((isPaid ? BoothifyTheme.violet : BoothifyTheme.textMuted).opacity(0.15), in: Capsule())
                            .overlay(Capsule().stroke((isPaid ? BoothifyTheme.violet : BoothifyTheme.textMuted).opacity(0.35), lineWidth: 0.8))
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.textMuted)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // ── Booth ────────────────────────────────────────────────
                SettingsSectionCard(title: "Booth", entranceOrder: 2) {
                    // Full per-event configuration (camera, branding, sharing,
                    // survey, PIN…) surfaced from the main settings: opens the
                    // 360 settings hub for the live event, or the latest one.
                    if let boothEvent = app.events.first(where: { $0.id == app.currentEventId }) ?? app.events.first {
                        globalSettingsRow(
                            icon: "slider.horizontal.3",
                            title: "360 Advanced Settings",
                            subtitle: boothEvent.name
                        ) {
                            app.push(.settings360Hub(eventId: boothEvent.id))
                        }
                    } else {
                        globalSettingsRow(
                            icon: "slider.horizontal.3",
                            title: "360 Advanced Settings",
                            subtitle: "Create an event first"
                        )
                    }
                    globalSettingsRow(icon: "camera.rotate", title: "Default Camera", subtitle: "Back · Mirrored selfie off")
                    globalSettingsRow(icon: "rosette", title: "Default Branding", subtitle: "Logo watermark off")
                    globalSettingsRow(icon: "square.and.arrow.up", title: "Default Sharing", subtitle: "Email + SMS templates")
                }

                // ── App ──────────────────────────────────────────────────
                SettingsSectionCard(title: "App", entranceOrder: 3) {
                    globalSettingsRow(icon: "faceid", title: "Face ID / PIN Lock", subtitle: "Protect operator panel")
                    globalSettingsRow(icon: "bell", title: "Notifications", subtitle: "Event alerts, delivery status")
                    globalSettingsRow(icon: "internaldrive", title: "Storage", subtitle: "Manage local cache")
                    globalSettingsRow(icon: "globe", title: "Language & Region", subtitle: Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "English")
                }

                // ── Support ──────────────────────────────────────────────
                SettingsSectionCard(title: "Support", entranceOrder: 4) {
                    globalSettingsRow(icon: "questionmark.circle", title: "Help Center", subtitle: "Guides & tutorials") {
                        openURL(BoothifyAPI.shared.baseURL.appending(path: "support"))
                    }
                    globalSettingsRow(icon: "envelope", title: "Contact Support", subtitle: "support@boothify.app") {
                        let subject = "Boothify support (v\(appVersion))"
                            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                        if let url = URL(string: "mailto:support@boothify.app?subject=\(subject)") {
                            openURL(url)
                        }
                    }
                    globalSettingsRow(icon: "sparkles", title: "What's New", subtitle: "v\(appVersion)")
                }

                // ── About ────────────────────────────────────────────────
                SettingsSectionCard(entranceOrder: 5) {
                    NavigationLink(destination: AboutBoothifyView()) {
                        HStack {
                            globalRowIcon("info.circle")
                            Text("About Boothify")
                                .font(.body)
                                .foregroundStyle(.white)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.textMuted)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    globalSettingsRow(icon: "hand.raised", title: "Privacy Policy", subtitle: nil) {
                        openURL(BoothifyAPI.shared.baseURL.appending(path: "privacy"))
                    }
                    globalSettingsRow(icon: "doc.text", title: "Terms of Service", subtitle: nil) {
                        openURL(BoothifyAPI.shared.baseURL.appending(path: "terms"))
                    }
                }

                // ── Sign Out ─────────────────────────────────────────────
                SettingsSectionCard(entranceOrder: 6) {
                    Button(role: .destructive) {
                        Haptics.tap(.medium)
                        confirmSignOut = true
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(BoothifyTheme.error)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Text("Boothify \(appVersion) · Powered by Servify Labs")
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, BoothifySpacing.xs)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.top, BoothifySpacing.sm)
            .padding(.bottom, BoothifySpacing.xl)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .confirmationDialog("Sign out of Boothify?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive) { app.signOut() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallView()
        }
    }

    /// Global settings row. Pass an `action` only when the row actually does
    /// something — the disclosure chevron is shown *only* then, so informational
    /// rows (version, language, defaults summary) don't promise navigation that
    /// never happens (no false affordance).
    @ViewBuilder
    private func globalSettingsRow(
        icon: String,
        title: String,
        subtitle: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        let content = HStack(spacing: 14) {
            globalRowIcon(icon)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
            }
            Spacer()
            if action != nil {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())

        if let action {
            Button {
                Haptics.tap()
                action()
            } label: { content }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func globalRowIcon(_ icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BoothifyTheme.surface2)
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(BoothifyTheme.violet)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Profile (pushed section)

private struct ProfileCardView: View {
    @Environment(AppState.self) private var app

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
        ZStack {
            AtmosphericBackground()

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
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
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
                            .init(color: Color(red: 0.10, green: 0.22, blue: 0.45).opacity(0.70), location: 0.45),
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
            profileStat(value: "\(totalPhotos)", label: "Videos", tint: BoothifyTheme.emerald)
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
        .glassSurface(radius: BoothifyRadius.tile)
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
            AtmosphericBackground()
            ProgressView()
                .tint(BoothifyTheme.violet)
        }
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
