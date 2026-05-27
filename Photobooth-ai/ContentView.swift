import SwiftUI

// Kept as a back-compat entry. RootView is the real composition root.
struct ContentView: View {
    var body: some View {
        RootView()
            .environment(AppState())
    }
}

#Preview {
    ContentView()
}
