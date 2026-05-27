import SwiftUI

@main
struct Photobooth_aiApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .preferredColorScheme(.dark)
                .tint(BoothifyTheme.violet)
                .task { await appState.bootstrapAuth() }
        }
    }
}
