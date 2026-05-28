import Foundation

/// Persisted Supabase session blob. Mirrors the response shape from
/// `/api/auth/apple` and `/api/auth/refresh`. Stored in Keychain, never
/// in UserDefaults.
struct AuthSession: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    /// Unix epoch seconds. Supabase returns absolute expiry, not TTL.
    let expiresAt: Int
    let user: AuthUser

    /// 60-second skew so we proactively refresh instead of getting a 401.
    var isExpired: Bool {
        Date().timeIntervalSince1970 >= Double(expiresAt) - 60
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }
}

struct AuthUser: Codable, Equatable {
    let id: String
    /// May be null when Apple shipped no email (private relay, post-first-login).
    /// AuthUser decoder must always tolerate null here — backend AM2 made it
    /// nullable too, removing the prior synthetic `apple_*@apple.local` workaround.
    let email: String?
    /// BM2 + backend AM2 — operator's display name from Apple's first-login
    /// payload. Optional in the wire response (backend column is nullable,
    /// not every session row has it backfilled).
    let fullName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case fullName = "full_name"
    }

    init(id: String, email: String? = nil, fullName: String? = nil) {
        self.id = id
        self.email = email
        self.fullName = fullName
    }
}
