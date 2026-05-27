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
    let email: String?
}
