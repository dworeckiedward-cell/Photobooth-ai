import Foundation
import CryptoKit

/// Thin client for `/api/auth/*`. Owns the network calls for Apple sign-in and
/// refresh — the actual session lifecycle (loading from Keychain at launch,
/// observing across views) lives on `AppState`.
@MainActor
final class AuthClient {
    static let shared = AuthClient()

    private var baseURL: URL { BoothifyAPI.shared.baseURL }
    private let session: URLSession
    private let jsonDecoder: JSONDecoder

    private init() {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        // Supabase returns snake_case; AuthSession.CodingKeys maps explicitly.
        self.jsonDecoder = dec
    }

    /// POST /api/auth/apple — exchanges Apple's identityToken + raw nonce for a Supabase session.
    ///
    /// `firstLoginEmail` / `firstLoginFullName` are non-nil only on the very
    /// first sign-in for this Apple ID + app. Backend should persist them on
    /// first arrival (idempotent backfill) — Apple never re-sends them and we
    /// permanently lose the email if we drop them here.
    func signInWithApple(
        identityToken: String,
        nonce: String,
        authorizationCode: String? = nil,
        firstLoginEmail: String? = nil,
        firstLoginFullName: String? = nil
    ) async throws -> AuthSession {
        struct Body: Encodable {
            let identityToken: String
            let nonce: String
            let authorizationCode: String?
            let firstLoginEmail: String?
            let firstLoginFullName: String?
            enum CodingKeys: String, CodingKey {
                case identityToken
                case nonce
                case authorizationCode = "authorization_code"
                case firstLoginEmail = "first_login_email"
                case firstLoginFullName = "first_login_full_name"
            }
        }
        return try await post(
            "/api/auth/apple",
            body: Body(
                identityToken: identityToken,
                nonce: nonce,
                authorizationCode: authorizationCode,
                firstLoginEmail: firstLoginEmail,
                firstLoginFullName: firstLoginFullName
            )
        )
    }

    /// POST /api/auth/refresh — exchanges a refresh_token for a new session.
    func refresh(refreshToken: String) async throws -> AuthSession {
        struct Body: Encodable { let refresh_token: String }
        return try await post("/api/auth/refresh", body: Body(refresh_token: refreshToken))
    }

    /// DELETE /api/auth/account — backend permanently deletes the user's
    /// Supabase row + cascades to events/photos/360 jobs. On success the caller
    /// should also clear local state (`AppState.signOut`, `AppleProfileCache.clear`).
    ///
    /// Returns `true` if the backend confirmed deletion. If the endpoint isn't
    /// implemented yet, surfaces an `APIError` so the UI can fall back to "we
    /// signed you out locally — finish removing your data by emailing us".
    func deleteAccount(accessToken: String) async throws {
        guard let url = URL(string: "/api/auth/account", relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: 0, message: "Non-HTTP response")
        }
        if (200..<300).contains(http.statusCode) { return }
        if http.statusCode == 401 { throw APIError.unauthorized }
        let msg = String(data: data, encoding: .utf8)
        throw APIError.serverError(status: http.statusCode, message: msg)
    }

    // MARK: - Nonce helpers
    //
    // Apple expects a SHA-256 hash of a random nonce in `request.nonce`.
    // The hashed value is embedded in the ID token's `nonce` claim. To verify
    // server-side via `supabase.auth.signInWithIdToken({ nonce })`, we send
    // the RAW (un-hashed) nonce — Supabase re-hashes it and compares.

    static func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, random.count, &random)
            precondition(status == errSecSuccess, "Failed to obtain secure random bytes")
            for byte in random where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte) % charset.count])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA-256 hex digest, used as the `request.nonce` to Apple.
    static func sha256(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Plumbing

    private func post<R: Decodable>(_ path: String, body: some Encodable) async throws -> R {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch let urlError as URLError {
            throw APIError.network(urlError)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: 0, message: "Non-HTTP response")
        }
        if (200..<300).contains(http.statusCode) {
            return try jsonDecoder.decode(R.self, from: data)
        }
        if http.statusCode == 401 { throw APIError.unauthorized }
        let msg = String(data: data, encoding: .utf8)
        throw APIError.serverError(status: http.statusCode, message: msg)
    }
}
