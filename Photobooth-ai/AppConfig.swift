import Foundation

/// Compile-time toggles that affect launch behavior. Kept tiny on purpose —
/// any flag here is a temporary hatch, not a feature switch.
enum AppConfig {
    /// When `false`, the app skips the LoginView gate and runs in local-only
    /// demo mode. Apple sign-in code (LoginView, AuthClient, KeychainStore,
    /// `/api/auth/apple`, the entitlement) is intentionally left intact and is
    /// re-activated by flipping this back to `true`.
    ///
    /// Default: ON in Release (App Store requirement).
    ///
    /// 🚨 TEMPORARY: in Debug builds the gate is OFF by default for
    /// pre-event testing without the backend auth round-trip. Set
    /// `BOOTHIFY_REQUIRE_AUTH=1` in the Xcode scheme env to force-test
    /// the Apple Sign In flow. Release behavior is unchanged — App Store
    /// submission still requires Sign in with Apple.
    /// See TODO-HUMAN.md for the revert instructions.
    static var authGateEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BOOTHIFY_REQUIRE_AUTH"] == "1" {
            return true
        }
        return false
        #else
        return true
        #endif
    }
}
