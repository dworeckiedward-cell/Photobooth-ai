import Foundation

/// 360 AI Booth domain types. The pipeline is mocked on-device today, but every
/// field on `Booth360Job` is shaped to map 1:1 to a future `booth360_jobs`
/// Supabase row + storage URLs. When the real render backend ships we swap
/// `MockBooth360RenderClient` for a real client that uploads raw footage and
/// polls a backend job endpoint.

// MARK: - Render status & steps

enum Booth360RenderStatus: String, Codable, CaseIterable, Hashable, Sendable {
    case idle, uploading, queued, processing, completed, failed

    var label: String {
        switch self {
        case .idle:       "Ready"
        case .uploading:  "Uploading"
        case .queued:     "Queued"
        case .processing: "Processing"
        case .completed:  "Completed"
        case .failed:     "Failed"
        }
    }

    var isTerminal: Bool { self == .completed || self == .failed }
}

/// Steps shown in the processing UI. Ordered intentionally — drives the progress
/// timeline. The mock client iterates through these; a real client will set the
/// `currentStep` based on backend job state.
enum Booth360ProcessingStep: String, Codable, CaseIterable, Hashable, Sendable {
    case uploading
    case stabilizing
    case slowMotion
    case cinematicEffects
    case soundtrackOverlays
    case sharePage

    var label: String {
        switch self {
        case .uploading:          "Uploading raw footage"
        case .stabilizing:        "Stabilizing video"
        case .slowMotion:         "Creating slow motion"
        case .cinematicEffects:   "Applying AI cinematic effects"
        case .soundtrackOverlays: "Adding soundtrack and overlays"
        case .sharePage:          "Preparing share page"
        }
    }

    var symbol: String {
        switch self {
        case .uploading:          "icloud.and.arrow.up.fill"
        case .stabilizing:        "rectangle.dashed"
        case .slowMotion:         "slowmo"
        case .cinematicEffects:   "wand.and.stars"
        case .soundtrackOverlays: "music.note"
        case .sharePage:          "link"
        }
    }
}

// MARK: - Job

/// A 360 AI Booth render job. MVP fields are populated by the mock client; the
/// rest are placeholders ready for the backend. Keep this shape stable — the real
/// backend will encode/decode the same JSON.
struct Booth360Job: Identifiable, Codable, Hashable, Sendable {
    /// `renderJobId` — primary key on the future backend table.
    let id: UUID
    let eventId: UUID

    var status: Booth360RenderStatus
    var currentStep: Booth360ProcessingStep?
    /// Overall job progress, 0...1.
    var progress: Double

    /// Local device file URI of the raw recording (mock today — we don't actually
    /// write a video file to disk yet).
    var rawVideoLocalURL: URL?
    /// Backend-stored raw upload URL (populated after upload succeeds).
    var uploadedRawVideoURL: URL?
    /// Backend-stored final-render URL (populated when status == .completed).
    var finalVideoURL: URL?
    /// Public guest-facing share page URL, e.g. `https://boothify.app/v/<short>`.
    var publicShareURL: URL?

    /// Settings captured at recording time. Frozen for reproducibility.
    var settingsSnapshot: AI360Settings
    /// Effect preset id used for this render (future — drives cinematic_neon, classic_glam, etc.)
    var effectPreset: String?
    var soundtrackId: String?
    /// Brand overlay applied to this render.
    var brandOverlay: BrandOverlaySettings

    var createdAt: Date
    var completedAt: Date?
    var errorMessage: String?

    /// Convenience: build a fresh job at recording-end time with everything
    /// snapshotted from the operator's current settings.
    init(eventId: UUID, settingsSnapshot: AI360Settings, brandOverlay: BrandOverlaySettings) {
        self.id = UUID()
        self.eventId = eventId
        self.status = .idle
        self.progress = 0
        self.settingsSnapshot = settingsSnapshot
        self.brandOverlay = brandOverlay
        self.createdAt = .now
    }
}

// MARK: - Render client (mock today, backend tomorrow)

/// Both `MockBooth360RenderClient` and a future `Booth360APIRenderClient` will
/// conform. Views call into this protocol — never directly to the mock — so
/// dropping in the real client is a single-line wiring change.
protocol Booth360RenderClient: Sendable {
    /// Drive the job through its render pipeline. Posts updates by mutating the
    /// job in `app.booth360Jobs` via `app.upsertJob(_:)`. Cancellation respected.
    func runPipeline(jobId: UUID, app: AppState) async
}

@MainActor
final class MockBooth360RenderClient: Booth360RenderClient {
    static let shared = MockBooth360RenderClient()
    private init() {}

    func runPipeline(jobId: UUID, app: AppState) async {
        let steps: [Booth360ProcessingStep] = [
            .uploading, .stabilizing, .slowMotion,
            .cinematicEffects, .soundtrackOverlays, .sharePage,
        ]
        let stepDuration: TimeInterval = 1.1

        for (i, step) in steps.enumerated() {
            if Task.isCancelled { return }
            guard var job = app.job(id: jobId) else { return }
            job.status = (step == .uploading) ? .uploading : .processing
            job.currentStep = step
            job.progress = Double(i) / Double(steps.count)
            app.upsertJob(job)
            try? await Task.sleep(for: .seconds(stepDuration))
        }

        if Task.isCancelled { return }
        guard var job = app.job(id: jobId) else { return }
        job.status = .completed
        job.currentStep = nil
        job.progress = 1.0
        job.completedAt = .now
        // Public share URL is a believable mock until the backend mints real ones.
        job.publicShareURL = URL(string: "https://boothify.app/v/\(jobId.uuidString.prefix(8).lowercased())")
        // `finalVideoURL` intentionally left nil — the Result screen detects nil
        // and shows the animated demo placeholder. Real client sets it here.
        app.upsertJob(job)
    }
}
