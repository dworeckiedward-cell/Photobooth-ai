import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

    // IM3: surface the first-login quiz once the user is past the auth gate
    // and `OnboardingStore.hasCompleted` is false. Re-checked when auth state
    // flips so re-installs / sign-outs get prompted again.
    @State private var onboardingPresented: Bool = false

    var body: some View {
        @Bindable var app = app
        Group {
            if app.isAuthLoading {
                AuthSplashView()
            } else if AppConfig.authGateEnabled && !app.isAuthenticated {
                // TODO: Re-enable Sign in with Apple before production multi-user launch.
                LoginView()
            } else {
                NavigationStack(path: $app.path) {
                    ModeSelectionView()
                        .navigationDestination(for: Route.self) { route in
                            destination(for: route)
                        }
                }
                // RA4 — Status HUD on top of the entire authed app. Only
                // renders pill when there's a real problem (offline / hot /
                // low battery / pending uploads). Tap-target is the pill
                // itself; expanding a multi-alert list is a future polish.
                .overlay(alignment: .top) {
                    StatusOverlay()
                        .allowsHitTesting(false)
                }
                .sheet(isPresented: $onboardingPresented) {
                    OnboardingQuizSheet { answers in
                        applyOnboardingDefaults(answers)
                    }
                    .interactiveDismissDisabled(false)
                }
                .task {
                    // Defer slightly so the navigation stack settles before
                    // the sheet pops — avoids first-frame flicker.
                    if !OnboardingStore.hasCompleted {
                        try? await Task.sleep(for: .milliseconds(350))
                        onboardingPresented = true
                    }
                }
            }
        }
    }

    /// IM3: translate quiz answers into sensible default app state. Today we
    /// only set the most universally-useful default (preferred template
    /// duration → bumps recordingDurationSeconds on AI360Settings so the
    /// FIRST event the operator creates inherits it). Per-mode and branding
    /// defaults are wired into event creation in a future sprint —
    /// preferences are stored either way.
    private func applyOnboardingDefaults(_ answers: OnboardingAnswers) {
        // No event exists yet at first login, so we stash preferences on
        // `OnboardingStore`; createEvent path can read them when it ships
        // a "first event uses onboarding defaults" hook. Mark this in
        // TODO-HUMAN if we want full preference propagation.
        OnboardingStore.save(answers)
    }

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

        // Settings tree
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

        // MVP add-ons
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

        // 360 AI Booth flow
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

/// Brief splash shown while AppState probes Keychain at launch. Prevents the
/// LoginView from flashing for a frame when a valid session is restored.
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
