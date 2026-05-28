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

    // MARK: - 360 jobs (M3)

    /// `POST /api/booth360/jobs` — multipart upload of the raw recording.
    /// Returns a backend-issued job DTO that the caller polls until completion.
    func uploadBooth360Job(
        rawVideoURL: URL,
        eventId: UUID,
        settings: AI360Settings
    ) async throws -> Booth360JobDTO {
        // Read the file off the main actor — even 10s @ 1080p is tens of MB.
        let data = try Data(contentsOf: rawVideoURL)

        let boundary = "boothify-360-\(UUID().uuidString)"
        var req = try makeRequest(path: "/api/booth360/jobs", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // JSON-encode the settings snapshot so backend stores it verbatim.
        let settingsData = (try? jsonEncoder.encode(settings)) ?? Data()
        let settingsJSON = String(data: settingsData, encoding: .utf8) ?? "{}"

        req.httpBody = buildMultipartBody(
            boundary: boundary,
            fields: [
                "eventId": eventId.uuidString,
                "settings": settingsJSON,
            ],
            files: [
                .init(name: "file",
                      filename: rawVideoURL.lastPathComponent,
                      mimeType: "video/quicktime",
                      data: data)
            ]
        )
        struct Wrapper: Decodable { let job: Booth360JobDTO }
        let wrapper: Wrapper = try await performDecoding(req)
        return wrapper.job
    }

    // MARK: - 360 direct upload (BM0)

    /// Response shape for `POST /api/booth360/uploads/sign`.
    struct UploadURLResponse: Decodable {
        let uploadURL: URL
        let uploadToken: String?
        let storagePath: String
        let shortCode: String
        let publicShareURL: URL
        let expectedContentType: String

        enum CodingKeys: String, CodingKey {
            case uploadURL = "upload_url"
            case uploadToken = "upload_token"
            case storagePath = "storage_path"
            case shortCode = "short_code"
            case publicShareURL = "public_share_url"
            case expectedContentType = "expected_content_type"
        }
    }

    /// Step 1 — ask the backend for a signed Supabase Storage URL we can PUT
    /// the rendered mp4 directly to. Bypasses Vercel's 4.5 MB body cap.
    /// Idempotent: same `clientJobId` returns the same `storagePath` +
    /// `shortCode` so retries don't allocate new objects.
    func requestUploadURL(
        eventSlug: String,
        clientJobId: String,
        contentType: String = "video/mp4"
    ) async throws -> UploadURLResponse {
        struct Body: Encodable {
            let eventSlug: String
            let clientJobId: String
            let contentType: String
            enum CodingKeys: String, CodingKey {
                case eventSlug = "event_slug"
                case clientJobId = "client_job_id"
                case contentType = "content_type"
            }
        }
        return try await request(
            "/api/booth360/uploads/sign",
            method: "POST",
            body: Body(eventSlug: eventSlug, clientJobId: clientJobId, contentType: contentType)
        )
    }

    /// Step 2 — PUT the rendered file directly to Supabase Storage.
    ///
    /// Uses `URLSession.uploadTask(with:fromFile:)` (file-backed, NOT memory-backed)
    /// so even big takes stream off disk instead of being loaded whole. Reports
    /// progress through the optional `onProgress` callback so the UI can keep
    /// the FFmpeg progress bar moving past the render phase.
    ///
    /// We deliberately don't go through `BoothifyAPI.session` here — the signed
    /// URL is on Supabase Storage's host, no Authorization header allowed.
    func uploadVideoDirect(
        fileURL: URL,
        to signedURL: URL,
        contentType: String = "video/mp4",
        onProgress: (@MainActor (Double) -> Void)? = nil
    ) async throws {
        var req = URLRequest(url: signedURL)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        // Supabase Storage upserts on signed PUT when the URL was created with
        // `upsert: true` (backend's sign endpoint does this). Setting the
        // header explicitly is belt-and-braces — Supabase ignores duplicates.
        req.setValue("true", forHTTPHeaderField: "x-upsert")

        let delegate = UploadProgressDelegate(onProgress: onProgress)
        // Use a transient session so the delegate's lifecycle is bounded by
        // this call — no leaks if the caller cancels.
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 300
        cfg.waitsForConnectivity = false
        let session = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.upload(for: req, fromFile: fileURL)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.serverError(status: 0, message: "Non-HTTP response from Supabase")
        }
        if !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "—"
            throw APIError.serverError(
                status: http.statusCode,
                message: "Supabase upload rejected: \(body)"
            )
        }
    }

    /// Step 3 — confirm the upload to the backend. Body is JSON (NOT
    /// multipart) so the route handler picks the AM1 direct-confirm branch
    /// instead of trying to parse a file from form-data.
    func confirmBooth360Job(
        storagePath: String,
        shortCode: String?,
        clientJobId: String,
        eventSlug: String,
        durationSeconds: Double?,
        metadata: AI360Settings?
    ) async throws -> Booth360JobDTO {
        struct Body: Encodable {
            let eventSlug: String
            let clientJobId: String
            let storagePath: String
            let shortCode: String?
            let durationSeconds: Double?
            let metadata: AI360Settings?
            enum CodingKeys: String, CodingKey {
                case eventSlug = "event_slug"
                case clientJobId = "client_job_id"
                case storagePath = "storage_path"
                case shortCode = "short_code"
                case durationSeconds = "duration_seconds"
                case metadata
            }
        }
        struct Wrapper: Decodable { let job: Booth360JobDTO }
        let wrapper: Wrapper = try await request(
            "/api/booth360/jobs",
            method: "POST",
            body: Body(
                eventSlug: eventSlug,
                clientJobId: clientJobId,
                storagePath: storagePath,
                shortCode: shortCode,
                durationSeconds: durationSeconds,
                metadata: metadata
            )
        )
        return wrapper.job
    }

    /// `POST /api/booth360/jobs/{id}/sms` — flag that iOS already sent the
    /// SMS via the operator's own Twilio (per-event, M5). Drives the "sent"
    /// counter in cloud status (BM4 on the backend).
    func markBooth360SMSSent(jobId: UUID, phone: String?) async throws {
        struct Body: Encodable { let phone: String? }
        struct Resp: Decodable { let ok: Bool }
        let _: Resp = try await request(
            "/api/booth360/jobs/\(jobId.uuidString)/sms",
            method: "POST",
            body: Body(phone: phone)
        )
    }

    /// `GET /api/booth360/jobs/{id}` — poll one job.
    func getBooth360Job(id: UUID) async throws -> Booth360JobDTO {
        struct Wrapper: Decodable { let job: Booth360JobDTO }
        let wrapper: Wrapper = try await request("/api/booth360/jobs/\(id.uuidString)")
        return wrapper.job
    }

    /// Polls `getBooth360Job` until terminal (completed / failed) or timeout.
    func pollBooth360JobUntilTerminal(
        id: UUID,
        intervalSeconds: Double = 2.0,
        maxAttempts: Int = 120,
        onUpdate: ((Booth360JobDTO) -> Void)? = nil
    ) async throws -> Booth360JobDTO {
        for _ in 0..<maxAttempts {
            let dto = try await getBooth360Job(id: id)
            onUpdate?(dto)
            let status = Booth360RenderStatus(rawValue: dto.status)
            if status?.isTerminal == true {
                return dto
            }
            try await Task.sleep(for: .seconds(intervalSeconds))
        }
        throw APIError.pollingTimedOut
    }

    /// `GET /api/events/{slug}/booth360-jobs` — list jobs for an event.
    func listEventBooth360Jobs(slug: String) async throws -> [Booth360JobDTO] {
        struct Wrapper: Decodable { let jobs: [Booth360JobDTO] }
        let wrapper: Wrapper = try await request("/api/events/\(slug)/booth360-jobs")
        return wrapper.jobs
    }

    /// `GET /api/events/{slug}/status` — IM2 rollup of pipeline counters.
    /// Backend not deployed yet → graceful 404 / decode failure handled by
    /// the caller, which falls back to a local snapshot.
    func eventStatus(slug: String) async throws -> EventCloudStatus {
        try await request("/api/events/\(slug)/status")
    }

    /// `PATCH /api/events/{slug}` — currently only used for share mode toggle.
    /// Returns the updated event.
    @discardableResult
    func updateEventShareMode(slug: String, shareMode: ShareMode) async throws -> Event {
        struct Body: Encodable {
            let shareMode: String
            enum CodingKeys: String, CodingKey { case shareMode = "share_mode" }
        }
        struct Wrapper: Decodable { let event: Event }
        let wrapper: Wrapper = try await request(
            "/api/events/\(slug)",
            method: "PATCH",
            body: Body(shareMode: shareMode.rawValue)
        )
        return wrapper.event
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

/// BM0 — URLSession delegate that forwards the upload byte counter to a
/// MainActor callback. Bounded lifetime (one per `uploadVideoDirect` call).
private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate {
    let onProgress: (@MainActor (Double) -> Void)?
    init(onProgress: (@MainActor (Double) -> Void)?) {
        self.onProgress = onProgress
    }
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend totalBytesExpectedToSend: Int64
    ) {
        guard let onProgress, totalBytesExpectedToSend > 0 else { return }
        let pct = max(0.0, min(1.0, Double(totalBytesSent) / Double(totalBytesExpectedToSend)))
        Task { @MainActor in onProgress(pct) }
    }
}

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
