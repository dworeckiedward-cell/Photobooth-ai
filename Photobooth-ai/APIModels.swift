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

/// How an event's media (photos + 360 videos) gets shared.
///
/// `.private` (default, safest): every guest gets a unique link to ONLY their
/// own media. `.public`: a single album link shows the entire event to anyone
/// with the URL. Operator picks per event in Settings.
enum ShareMode: String, Codable, Hashable, Sendable, CaseIterable {
    case `private`
    case `public`

    var label: String {
        switch self {
        case .private: "Private (per-guest links)"
        case .public:  "Public (single album link)"
        }
    }
}

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
    /// M3: share mode for the entire event (private = per-guest links,
    /// public = single album link). Optional in the wire format so older
    /// backend payloads still decode — iOS defaults to `.private` when nil.
    var shareMode: ShareMode?

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
        case shareMode = "share_mode"
    }

    /// Effective share mode — falls back to `.private` if the backend hasn't
    /// shipped the column yet.
    var effectiveShareMode: ShareMode { shareMode ?? .private }

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
            shareMode: .private,
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

// MARK: - 360 jobs (M3)

/// Wire response for `POST /api/booth360/jobs` and `GET /api/booth360/jobs/{id}`.
/// Mirrors a subset of the in-memory `Booth360Job` — backend owns canonical
/// state; iOS reconciles into the local job after each fetch.
struct Booth360JobDTO: Codable, Sendable {
    let id: UUID
    let eventId: UUID
    let status: String          // raw value of Booth360RenderStatus
    let currentStep: String?    // raw value of Booth360ProcessingStep
    let progress: Double
    let rawVideoUrl: String?
    let finalVideoUrl: String?
    let publicShareUrl: String?
    let createdAt: Date?
    let completedAt: Date?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case eventId = "event_id"
        case status
        case currentStep = "current_step"
        case progress
        case rawVideoUrl = "raw_video_url"
        case finalVideoUrl = "final_video_url"
        case publicShareUrl = "public_share_url"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case errorMessage = "error_message"
    }
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
