import Foundation

/// Compile-time toggles that affect launch behavior. Kept tiny on purpose —
/// any flag here is a temporary hatch, not a feature switch.
enum AppConfig {
    /// When `false`, the app skips the LoginView gate and runs in local-only
    /// demo mode. Apple sign-in code (LoginView, AuthClient, KeychainStore,
    /// `/api/auth/apple`, the entitlement) is intentionally left intact and is
    /// re-activated by flipping this back to `true`.
    ///
    /// Default: ON (App Store requirement). IM4: in DEBUG builds this can be
    /// overridden by setting the environment variable `BOOTHIFY_BYPASS_AUTH=1`
    /// in the Xcode scheme — useful for on-device testing of camera / montage
    /// before the backend auth + Supabase Apple provider are wired.
    static var authGateEnabled: Bool {
        let baseline = true
        #if DEBUG
        if ProcessInfo.processInfo.environment["BOOTHIFY_BYPASS_AUTH"] == "1" {
            return false
        }
        #endif
        return baseline
    }
}
