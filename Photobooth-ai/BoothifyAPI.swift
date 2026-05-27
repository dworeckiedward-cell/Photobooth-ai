import Foundation
import UIKit

/// Single source of truth for talking to the Boothify backend. iOS-first product;
/// see `docs/api-contract.md` in the webapp repo for the wire format.
///
/// Usage:
/// ```
/// let event = try await BoothifyAPI.shared.createEvent(name: "Anna & Tom")
/// let photoId = try await BoothifyAPI.shared.uploadPhoto(image: img, eventId: event.id, style: .astronauta)
/// try await BoothifyAPI.shared.generatePhoto(photoId: photoId, style: .astronauta)
/// let photo = try await BoothifyAPI.shared.pollUntilCompleted(photoId: photoId)
/// ```
@MainActor
final class BoothifyAPI {
    static let shared = BoothifyAPI()

    /// Base URL. Override at app launch via Info.plist key `BOOTHIFY_API_BASE_URL` or
    /// programmatically via `BoothifyAPI.shared.configure(baseURL:)`.
    private(set) var baseURL: URL

    /// Read the current session (returns the Bearer access token if signed in).
    /// AppState installs this at launch; tests can swap in a fixed provider.
    var sessionProvider: (() -> AuthSession?)? = nil

    /// Async refresh callback. Invoked on 401 once per request. AppState wires
    /// this to call AuthClient.refresh + persist the new session, then return
    /// the fresh access token. Return nil to surface the 401 to the caller.
    var refreshHandler: (() async -> String?)? = nil

    private let session: URLSession
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    private init() {
        let bundleBase = Bundle.main.object(forInfoDictionaryKey: "BOOTHIFY_API_BASE_URL") as? String
        self.baseURL = URL(string: bundleBase ?? "http://localhost:3000")!

        let config = URLSessionConfiguration.default
        // Fail fast when the dev backend isn't reachable — otherwise the user sees
        // a permanent spinner instead of an error.
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.jsonDecoder = dec

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.jsonEncoder = enc
    }

    /// Override base URL at runtime (e.g. dev settings screen).
    func configure(baseURL: URL) {
        self.baseURL = baseURL
    }

    // MARK: - Public URLs (no API call — just builds the string the webapp serves at /p/...)

    /// Build the public guest-facing result page URL. iOS uses this for the QR code.
    func publicResultURL(photoId: UUID) -> URL {
        baseURL.appending(path: "p").appending(path: photoId.uuidString.lowercased())
    }

    // MARK: - Events

    /// `POST /api/events` — create a new event.
    func createEvent(name: String) async throws -> Event {
        struct Body: Encodable { let name: String }
        struct Wrapper: Decodable { let event: Event }
        let wrapper: Wrapper = try await request(
            "/api/events",
            method: "POST",
            body: Body(name: name)
        )
        return wrapper.event
    }

    /// `GET /api/events/recent` — up to 8 most recent active events.
    func listRecentEvents() async throws -> [Event] {
        struct Wrapper: Decodable { let events: [Event] }
        let wrapper: Wrapper = try await request("/api/events/recent")
        return wrapper.events
    }

    /// `GET /api/events/[slug]` — full event detail.
    func getEvent(slug: String) async throws -> Event {
        struct Wrapper: Decodable { let event: Event }
        let wrapper: Wrapper = try await request("/api/events/\(slug)")
        return wrapper.event
    }

    /// `GET /api/events/[slug]/photos` — photos in an event.
    func listEventPhotos(
        slug: String,
        status: PhotoStatusQuery = .completed,
        limit: Int = 100,
        offset: Int = 0
    ) async throws -> PhotoList {
        let q = "?status=\(status.rawValue)&limit=\(limit)&offset=\(offset)"
        return try await request("/api/events/\(slug)/photos\(q)")
    }

    // MARK: - Photos

    /// `POST /api/photos/upload` — multipart upload. Returns the new photoId.
    func uploadPhoto(
        imageData: Data,
        eventId: UUID,
        style: PhotoStyle
    ) async throws -> UUID {
        let boundary = "boothify-\(UUID().uuidString)"
        var req = try makeRequest(path: "/api/photos/upload", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = buildMultipartBody(
            boundary: boundary,
            fields: [
                "eventId": eventId.uuidString,
                "style": style.rawValue,
            ],
            files: [
                .init(name: "file", filename: "capture.jpg", mimeType: "image/jpeg", data: imageData)
            ]
        )

        struct Wrapper: Decodable { let photoId: UUID }
        let wrapper: Wrapper = try await performDecoding(req)
        return wrapper.photoId
    }

    /// `POST /api/photos/generate` — fires Gemini synchronously (up to 60s).
    @discardableResult
    func generatePhoto(photoId: UUID, style: PhotoStyle) async throws -> GenerateResult {
        struct Body: Encodable { let photoId: String; let style: String }
        return try await request(
            "/api/photos/generate",
            method: "POST",
            body: Body(photoId: photoId.uuidString, style: style.rawValue)
        )
    }

    /// `GET /api/photos/[id]` — poll once.
    func getPhoto(id: UUID) async throws -> Photo {
        try await request("/api/photos/\(id.uuidString)")
    }

    /// Polls `getPhoto` until status reaches `completed` or `failed`.
    func pollUntilCompleted(
        photoId: UUID,
        intervalSeconds: Double = 1.0,
        maxAttempts: Int = 60
    ) async throws -> Photo {
        for _ in 0..<maxAttempts {
            let photo = try await getPhoto(id: photoId)
            if photo.status == .completed || photo.status == .failed {
                return photo
            }
            try await Task.sleep(for: .seconds(intervalSeconds))
        }
        throw APIError.pollingTimedOut
    }

    /// `POST /api/photos/[id]/email`
    func sendEmail(photoId: UUID, email: String) async throws {
        struct Body: Encodable { let email: String }
        struct Resp: Decodable { let success: Bool; let mode: String? }
        let _: Resp = try await request(
            "/api/photos/\(photoId.uuidString)/email",
            method: "POST",
            body: Body(email: email)
        )
    }

    /// `POST /api/photos/[id]/sms`
    func sendSMS(photoId: UUID, phone: String) async throws {
        struct Body: Encodable { let phone: String }
        struct Resp: Decodable { let success: Bool; let mode: String? }
        let _: Resp = try await request(
            "/api/photos/\(photoId.uuidString)/sms",
            method: "POST",
            body: Body(phone: phone)
        )
    }

    // MARK: - Quota

    /// `GET /api/quota/gemini` — usage + budget snapshot.
    func getGeminiQuota() async throws -> GeminiQuota {
        try await request("/api/quota/gemini")
    }

    // MARK: - Core request plumbing

    private func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("ios/\(appVersion)", forHTTPHeaderField: "X-Boothify-Client")
        if let token = sessionProvider?()?.accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    /// Generic JSON-in / JSON-out request.
    private func request<R: Decodable>(
        _ path: String,
        method: String = "GET",
        body: (some Encodable)? = Optional<EmptyBody>.none
    ) async throws -> R {
        var req = try makeRequest(path: path, method: method)
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try jsonEncoder.encode(body)
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await performDecoding(req)
    }

    private func performDecoding<R: Decodable>(_ req: URLRequest) async throws -> R {
        let (data, response) = try await performRaw(req, allowRefresh: true)
        do {
            return try jsonDecoder.decode(R.self, from: data)
        } catch {
            if let envelope = try? jsonDecoder.decode(GenerateErrorEnvelope.self, from: data),
               envelope.success == false {
                throw APIError.generationFailed(
                    kind: envelope.error?.kind ?? "UNKNOWN",
                    message: envelope.error?.message ?? "Unknown failure"
                )
            }
            _ = response
            throw APIError.decoding(error)
        }
    }

    /// Sends the request, surfaces non-2xx as `APIError`, returns raw `(data, response)`.
    /// On 401, attempts a single refresh via `refreshHandler` and retries with the new token.
    private func performRaw(_ req: URLRequest, allowRefresh: Bool) async throws -> (Data, HTTPURLResponse) {
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
            return (data, http)
        }

        // 401: try refresh once. If it succeeds, retry the original request with
        // the fresh access token. If refresh returns nil or also fails, surface
        // unauthorized so AppState can sign the user out.
        if http.statusCode == 401, allowRefresh, let refresh = refreshHandler {
            if let newToken = await refresh() {
                var retry = req
                retry.setValue("Bearer \(newToken)", forHTTPHeaderField: "Authorization")
                return try await performRaw(retry, allowRefresh: false)
            }
            throw APIError.unauthorized
        }

        let errorMessage = extractErrorMessage(from: data)

        switch http.statusCode {
        case 401: throw APIError.unauthorized
        case 429:
            let resetIn = extractRateLimitReset(from: data)
            throw APIError.rateLimited(resetIn: resetIn)
        case 400..<500: throw APIError.clientError(status: http.statusCode, message: errorMessage)
        default: throw APIError.serverError(status: http.statusCode, message: errorMessage)
        }
    }

    private func extractErrorMessage(from data: Data) -> String? {
        if let envelope = try? jsonDecoder.decode(SimpleErrorEnvelope.self, from: data) {
            return envelope.error
        }
        return String(data: data, encoding: .utf8)
    }

    private func extractRateLimitReset(from data: Data) -> Int? {
        struct RL: Decodable { let resetIn: Int? }
        return (try? jsonDecoder.decode(RL.self, from: data))?.resetIn
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    // MARK: - Multipart

    private struct MultipartFile {
        let name: String
        let filename: String
        let mimeType: String
        let data: Data
    }

    private func buildMultipartBody(
        boundary: String,
        fields: [String: String],
        files: [MultipartFile]
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"
        for (key, value) in fields {
            body.append("--\(boundary)\(crlf)")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\(crlf)\(crlf)")
            body.append("\(value)\(crlf)")
        }
        for file in files {
            body.append("--\(boundary)\(crlf)")
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.filename)\"\(crlf)")
            body.append("Content-Type: \(file.mimeType)\(crlf)\(crlf)")
            body.append(file.data)
            body.append(crlf)
        }
        body.append("--\(boundary)--\(crlf)")
        return body
    }
}

// MARK: - Helper extensions

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}

private struct EmptyBody: Encodable {}

private struct SimpleErrorEnvelope: Decodable {
    let error: String?
}

private struct GenerateErrorEnvelope: Decodable {
    let success: Bool?
    let error: Inner?
    struct Inner: Decodable {
        let kind: String?
        let message: String?
    }
}
