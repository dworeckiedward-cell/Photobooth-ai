import Foundation

/// Compile-time toggles that affect launch behavior. Kept tiny on purpose —
/// any flag here is a temporary hatch, not a feature switch.
enum AppConfig {
    /// When `false`, the app skips the LoginView gate and runs in local-only
    /// demo mode. Apple sign-in code (LoginView, AuthClient, KeychainStore,
    /// `/api/auth/apple`, the entitlement) is intentionally left intact and is
    /// re-activated by flipping this back to `true`.
    ///
    /// TODO: Re-enable Sign in with Apple before production multi-user launch.
    /// To restore:
    ///   1. Set `authGateEnabled = true` here.
    ///   2. Verify Apple provider is enabled in Supabase Auth (see audit doc).
    ///   3. Build & ship — the existing AppState/RootView wiring takes over.
    static let authGateEnabled: Bool = true
}
