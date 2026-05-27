import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var app

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
                .overlay(alignment: .top) {
                    if app.isDemoMode {
                        DemoModeBanner()
                    }
                }
            }
        }
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

/// Visible reminder that the LoginView gate is bypassed. Surfaces while
/// `AppConfig.authGateEnabled == false`. Backend-touching calls outside the
/// AppState short-circuits will still 401 — this pill makes that visible.
///
/// TODO: Re-enable Sign in with Apple before production multi-user launch.
private struct DemoModeBanner: View {
    var body: some View {
        Text("DEMO MODE · sign-in disabled")
            .font(.caption2.weight(.bold))
            .kerning(0.8)
            .foregroundStyle(BoothifyTheme.amber)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(BoothifyTheme.amber.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.45), lineWidth: 0.5))
            .padding(.top, 4)
            .accessibilityLabel("Demo mode. Sign-in temporarily disabled.")
    }
}

#Preview {
    RootView()
        .environment(AppState())
}
