import SwiftUI
import Combine

@main
struct Photobooth_aiApp: App {
    @State private var appState = AppState()
    @State private var networkMonitor = NetworkMonitor.shared

    init() {
        // RA3 — boot Sentry before any other SDK or view work so we
        // capture crashes that happen during early init. No-op when the
        // BOOTHIFY_SENTRY_DSN Info.plist key is unset (dev / first install).
        SentryClient.shared.start()
        SentryClient.shared.breadcrumb("app launched", category: "lifecycle")
        NotificationManager.shared.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(BoothifyTheme.violet)
                .task { await appState.bootstrapAuth() }
                .onChange(of: networkMonitor.isConnected) { wasConnected, isConnected in
                    // When network is restored, replay any photos queued while offline.
                    if isConnected && !wasConnected {
                        PhotoUploadQueue.shared.replayPending(app: appState)
                    }
                }
        }
    }
}
