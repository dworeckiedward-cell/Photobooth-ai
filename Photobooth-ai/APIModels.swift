import Foundation

/// Wire-format DTOs that match `docs/api-contract.md` in the webapp. These are the
/// canonical iOS domain types — there is no separate "domain model" layer. The webapp
/// is the source of truth; iOS adapts to whatever shape the API returns.

// MARK: - Query helper

/// Query parameter values for `GET /api/events/[slug]/photos?status=...`.
enum PhotoStatusQuery: String, Sendable {
    case all, completed, generating, failed, uploaded, pending
}

// MARK: - Event

struct Event: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var slug: String
    var totalPhotos: Int
    var completedPhotos: Int
    var failedPhotos: Int?
    var maxPhotos: Int?
    var isActive: Bool?
    var brandingLogoUrl: String?
    var expiresAt: Date?
    var createdAt: Date
    /// Only populated by `/api/events/[slug]` and `/api/events/recent`.
    var thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case totalPhotos = "total_photos"
        case completedPhotos = "completed_photos"
        case failedPhotos = "failed_photos"
        case maxPhotos = "max_photos"
        case isActive = "is_active"
        case brandingLogoUrl = "branding_logo_url"
        case expiresAt = "expires_at"
        case createdAt = "created_at"
        case thumbnailUrl = "thumbnail_url"
    }

    /// Demo-mode-only constructor — builds an in-memory `Event` without hitting
    /// the backend. Used while the LoginView gate is temporarily bypassed
    /// (see `AppConfig.authGateEnabled`). Backend-bound flows (photo upload,
    /// generate, share) will still fail with 401 because no real session exists.
    ///
    /// TODO: Re-enable Sign in with Apple before production multi-user launch.
    static func localDemo(name: String) -> Event {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let slug = trimmed
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return Event(
            id: UUID(),
            name: trimmed,
            slug: slug.isEmpty ? "demo-event" : slug,
            totalPhotos: 0,
            completedPhotos: 0,
            failedPhotos: 0,
            maxPhotos: 1000,
            isActive: true,
            brandingLogoUrl: nil,
            expiresAt: Calendar.current.date(byAdding: .day, value: 7, to: .now),
            createdAt: .now,
            thumbnailUrl: nil,
        )
    }
}

// MARK: - Photo

struct Photo: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var style: PhotoStyle
    var status: PhotoStatus
    var generatedUrl: String?
    var errorMessage: String?
    var generationTimeMs: Int?
    var createdAt: Date?

    /// Convenience: returns generated URL as a real `URL` if parseable.
    var generatedURL: URL? {
        guard let s = generatedUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    enum CodingKeys: String, CodingKey {
        case id, style, status
        case generatedUrl = "generated_url"
        case errorMessage = "error_message"
        case generationTimeMs = "generation_time_ms"
        case createdAt = "created_at"
    }
}

struct PhotoList: Codable, Sendable {
    let photos: [Photo]
    let total: Int
    let limit: Int
    let offset: Int
}

// MARK: - Generate

struct GenerateResult: Codable, Sendable {
    let success: Bool
    let generatedUrl: String?
    let generationTimeMs: Int?
}

// MARK: - Quota

struct GeminiQuota: Codable, Sendable {
    let today: Window
    let month: Window
    let photosRemaining: Int
    let constraint: Constraint

    struct Window: Codable, Sendable {
        let tokens: Int
        let tokensLimit: Int?
        let generations: Int?
        let successful: Int?
        let costUsd: Double?
        let budgetLimitUsd: Double?

        enum CodingKeys: String, CodingKey {
            case tokens
            case tokensLimit = "tokens_limit"
            case generations, successful
            case costUsd = "cost_usd"
            case budgetLimitUsd = "budget_limit_usd"
        }
    }

    struct Constraint: Codable, Sendable {
        let type: String
        let usagePct: Double
        let warning: Bool
        let critical: Bool

        enum CodingKeys: String, CodingKey {
            case type
            case usagePct = "usage_pct"
            case warning, critical
        }
    }

    enum CodingKeys: String, CodingKey {
        case today, month
        case photosRemaining = "photos_remaining"
        case constraint
    }
}
