import Foundation

/// Apple Sign In only ships `email` and `fullName` THE FIRST TIME a user
/// authorizes the app. Every subsequent login returns nil for both. If we
/// don't persist them immediately on first-login we lose them forever.
///
/// This cache stores the bare minimum locally so we can re-send to the
/// backend on later logins (idempotent backfill) and so the AccountSettings
/// UI can show a friendly identity even after a session refresh.
///
/// Tokens still live in `KeychainStore`. This cache is plain UserDefaults —
/// email/name aren't secrets and Keychain churn isn't worth it.
enum AppleProfileCache {
    private static let emailKey    = "boothify.appleProfile.email"
    private static let fullNameKey = "boothify.appleProfile.fullName"
    private static let userIdKey   = "boothify.appleProfile.appleUserId"

    /// Stash the profile attributes from a fresh `ASAuthorizationAppleIDCredential`.
    /// Safe to call repeatedly — only writes non-nil values, never clobbers an
    /// existing email/name with nil (which is what Apple returns on every
    /// non-first login).
    static func persistFirstLogin(userId: String, email: String?, fullName: String?) {
        let defaults = UserDefaults.standard
        defaults.set(userId, forKey: userIdKey)
        if let email, !email.isEmpty {
            defaults.set(email, forKey: emailKey)
        }
        if let fullName, !fullName.isEmpty {
            defaults.set(fullName, forKey: fullNameKey)
        }
    }

    static var cachedEmail: String? {
        UserDefaults.standard.string(forKey: emailKey)
    }

    static var cachedFullName: String? {
        UserDefaults.standard.string(forKey: fullNameKey)
    }

    static var cachedAppleUserId: String? {
        UserDefaults.standard.string(forKey: userIdKey)
    }

    /// Wipe local profile cache (used by Sign Out + Delete Account flows).
    static func clear() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: emailKey)
        defaults.removeObject(forKey: fullNameKey)
        defaults.removeObject(forKey: userIdKey)
    }
}
