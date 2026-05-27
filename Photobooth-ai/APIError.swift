import Foundation

/// Errors surfaced by `BoothifyAPI`. See `docs/api-contract.md` in the webapp for the
/// shape of error payloads.
enum APIError: Error, LocalizedError {
    /// The URL couldn't be built. Programming error; should never reach production.
    case invalidURL

    /// Transport-level failure (DNS, offline, TLS) — wraps the underlying URLError.
    case network(URLError)

    /// Response body couldn't be decoded into the expected type.
    case decoding(Error)

    /// 401 — missing or wrong X-Boothify-API-Secret.
    case unauthorized

    /// 429 — rate-limited. `resetIn` is milliseconds until the bucket resets (when known).
    case rateLimited(resetIn: Int?)

    /// 4xx — typically validation error. `message` comes from `{"error": "..."}`.
    case clientError(status: Int, message: String?)

    /// 5xx — server-side problem. Retryable with backoff.
    case serverError(status: Int, message: String?)

    /// Photo generation failed inside Gemini. Carried in `{"success": false, "error": {kind, message}}`.
    case generationFailed(kind: String, message: String)

    /// Polling gave up before status reached a terminal state.
    case pollingTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid request URL"
        case .network(let urlError):
            // Surface common dev-time failures in human language. The default
            // .localizedDescription is too generic (e.g. "Could not connect to the server").
            switch urlError.code {
            case .cannotConnectToHost, .cannotFindHost, .networkConnectionLost:
                return "Boothify backend isn't reachable. Make sure the webapp dev server is running and BOOTHIFY_API_BASE_URL points at it."
            case .notConnectedToInternet:
                return "No internet connection."
            case .timedOut:
                return "Backend request timed out. The server may be busy or unreachable."
            default:
                return urlError.localizedDescription
            }
        case .decoding(let err): return "Response decoding failed: \(err)"
        case .unauthorized: return "Unauthorized — check API secret"
        case .rateLimited(let resetIn):
            if let r = resetIn { return "Rate limited — try again in \(r / 1000)s" }
            return "Rate limited — try again shortly"
        case .clientError(let status, let message): return message ?? "Client error (\(status))"
        case .serverError(let status, let message): return message ?? "Server error (\(status))"
        case .generationFailed(let kind, let message): return "Generation failed [\(kind)]: \(message)"
        case .pollingTimedOut: return "Photo generation took too long"
        }
    }

    /// True when the caller can retry after a delay. Network and 5xx are retryable;
    /// 4xx (validation) and decoding errors are not.
    var isRetryable: Bool {
        switch self {
        case .network, .serverError, .pollingTimedOut: return true
        case .rateLimited: return true
        case .invalidURL, .decoding, .unauthorized, .clientError, .generationFailed: return false
        }
    }
}
