import Foundation
import os.log
import UIKit  // QW7 — UINotificationFeedbackGenerator.FeedbackType.success

/// BM0 — orchestrates the post-render cloud upload (sign → PUT → confirm).
///
/// `Booth360FFmpegRenderClient` calls `enqueue(jobId:)` once it has a local
/// `finalVideoURL`. The uploader takes over from there: marks the job
/// `.uploading`, runs the three backend calls, and on success swaps the
/// mock `publicShareURL` for the real one returned by `/api/booth360/jobs`.
///
/// On failure the job stays around with `cloudUploadStatus = .failed` so
/// `Booth360UploadQueue` (BM1) can retry — either auto on next launch or
/// when the operator taps "Send again".
@MainActor
final class Booth360CloudUploader {
    static let shared = Booth360CloudUploader()

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Booth360CloudUploader")

    /// Per-job in-flight task tracker — prevents a manual "Send again" tap
    /// from racing with the auto-retry from BM1's queue restart.
    private var inFlight: [UUID: Task<Void, Never>] = [:]

    private init() {}

    /// Kick off (or re-kick) the upload for `jobId`. Idempotent: if the same
    /// job is already mid-upload, no-op. Always non-blocking — returns
    /// immediately while the actual sign/PUT/confirm runs on a Task.
    func enqueue(jobId: UUID, app: AppState) {
        guard inFlight[jobId] == nil else {
            log.debug("upload already in flight for \(jobId.uuidString, privacy: .public)")
            return
        }
        // Explicit Void return — `self?.runOnce(...)` yields `()?` via
        // optional chaining which doesn't match `Task<Void, Never>`.
        let task: Task<Void, Never> = Task { [weak self] in
            guard let self else { return }
            await self.runOnce(jobId: jobId, app: app)
        }
        inFlight[jobId] = task
    }

    /// Wait for an enqueued upload to finish (used in BM1 queue replay).
    /// If nothing's in flight, returns immediately.
    func awaitCompletion(jobId: UUID) async {
        if let t = inFlight[jobId] {
            await t.value
        }
    }

    /// Single attempt. Loops the 3 steps with bounded retry per step.
    /// BM1 layers another retry on top (the persistent queue) so partial
    /// failures don't ghost an upload mid-event.
    private func runOnce(jobId: UUID, app: AppState) async {
        defer { inFlight[jobId] = nil }

        guard var job = app.job(id: jobId),
              let localFile = job.finalVideoURL,
              FileManager.default.fileExists(atPath: localFile.path) else {
            log.warning("nothing to upload for \(jobId.uuidString, privacy: .public)")
            return
        }
        guard let event = app.event(id: job.eventId) else {
            log.warning("event missing for job \(jobId.uuidString, privacy: .public)")
            return
        }

        // Mark uploading + clear any prior error.
        job.cloudUploadStatus = .uploading
        job.cloudUploadError = nil
        app.upsertJob(job)

        // P4 — breadcrumb the start of each upload attempt. Event slug
        // is an opaque identifier, not PII; job-id helps correlate with
        // the matching `render completed` crumb a few seconds earlier.
        SentryClient.shared.breadcrumb(
            "upload start",
            category: "upload",
            data: [
                "job_id": String(jobId.uuidString.prefix(8)),
                "event_slug": event.slug,
            ]
        )

        // Step 1 — sign
        let signed: BoothifyAPI.UploadURLResponse
        do {
            signed = try await retry(label: "sign", attempts: 3) {
                try await BoothifyAPI.shared.requestUploadURL(
                    eventSlug: event.slug,
                    clientJobId: job.clientJobId,
                    contentType: "video/mp4"
                )
            }
        } catch {
            await markFailed(jobId: jobId, app: app, step: "sign", error: error)
            return
        }

        // Persist storage path even if PUT fails — next attempt reuses it
        // because the backend is idempotent on (event, client_job_id).
        if var live = app.job(id: jobId) {
            live.cloudStoragePath = signed.storagePath
            app.upsertJob(live)
        }

        // Step 2 — direct PUT to Supabase Storage
        do {
            try await retry(label: "put", attempts: 3) {
                try await BoothifyAPI.shared.uploadVideoDirect(
                    fileURL: localFile,
                    to: signed.uploadURL,
                    contentType: signed.expectedContentType,
                    onProgress: { [jobId] pct in
                        // Reflect the upload portion onto job.progress so the
                        // post-render UI keeps moving. Render itself ran 0..1
                        // already; we let the upload share the same bar.
                        guard var live = app.job(id: jobId) else { return }
                        live.progress = pct
                        app.upsertJob(live)
                    }
                )
            }
        } catch {
            await markFailed(jobId: jobId, app: app, step: "put", error: error)
            return
        }

        // Step 3 — confirm. Returns the backend DTO with the real share URL.
        let dto: Booth360JobDTO
        do {
            dto = try await retry(label: "confirm", attempts: 3) {
                try await BoothifyAPI.shared.confirmBooth360Job(
                    storagePath: signed.storagePath,
                    shortCode: signed.shortCode,
                    clientJobId: job.clientJobId,
                    eventSlug: event.slug,
                    durationSeconds: nil,
                    metadata: job.settingsSnapshot
                )
            }
        } catch {
            await markFailed(jobId: jobId, app: app, step: "confirm", error: error)
            return
        }

        // Success — swap mock share URL for the real one, clear error state.
        guard var live = app.job(id: jobId) else { return }
        live.cloudUploadStatus = .uploaded
        live.cloudUploadError = nil
        live.progress = 1
        // QW7 — gentle success haptic on cloud confirmation. Operator may
        // have moved on to recording the next guest; this is their cue
        // that the previous take has reached the cloud and is shareable.
        Haptics.notify(.success)
        if let real = URL(string: dto.publicShareUrl ?? "") {
            live.publicShareURL = real
        } else {
            // Backend returned no share URL but confirm itself succeeded —
            // keep whatever mock we had; UI still works.
        }
        app.upsertJob(live)
        // P4 — success breadcrumb. Pairs with `upload start`; in a Sentry
        // event you can see the time-to-cloud per take.
        SentryClient.shared.breadcrumb(
            "upload success",
            category: "upload",
            data: ["job_id": String(jobId.uuidString.prefix(8))]
        )
        // Once a job is uploaded, drop it from the persistent queue (BM1).
        Booth360UploadQueue.shared.remove(jobId: jobId)
    }

    private func markFailed(jobId: UUID, app: AppState, step: String, error: Error) async {
        log.error("upload \(step, privacy: .public) failed for \(jobId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        // P4 — leading breadcrumb so the captured error event includes the
        // failure context in its own crumb timeline. capture() ships the
        // exception; the crumb keeps it visible in the parent scope too.
        SentryClient.shared.breadcrumb(
            "upload failed (\(step))",
            category: "upload",
            data: ["job_id": String(jobId.uuidString.prefix(8))]
        )
        // RA3 — report to Sentry with context. Only after retries are
        // exhausted so transient blips don't spam.
        SentryClient.shared.capture(error, context: [
            "phase": "booth360_upload",
            "step": step,
            "job_id": jobId.uuidString,
        ])
        guard var live = app.job(id: jobId) else { return }
        live.cloudUploadStatus = .failed
        live.cloudUploadError = "\(step) failed: \(error.localizedDescription)"
        app.upsertJob(live)
        // BM1: persist for retry across app launches.
        Booth360UploadQueue.shared.enqueue(jobId: jobId)
    }

    // MARK: - Retry helper

    /// Exponential backoff: 1s, 3s, 9s (or fewer if `attempts` < 3).
    /// We refresh on 401 implicitly — `BoothifyAPI.performRaw` already wires
    /// the refresh handler on first 401. If refresh fails too the caller's
    /// next attempt sees 401 again and we surface it.
    private func retry<T>(
        label: String,
        attempts: Int,
        operation: () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        while attempt < attempts {
            do {
                return try await operation()
            } catch {
                attempt += 1
                lastError = error
                if attempt >= attempts { break }
                let delaySec = pow(3.0, Double(attempt - 1))   // 1, 3, 9
                log.warning("\(label, privacy: .public) attempt \(attempt) failed, retrying in \(delaySec)s: \(error.localizedDescription, privacy: .public)")
                try? await Task.sleep(for: .seconds(delaySec))
            }
        }
        throw lastError ?? APIError.serverError(status: 0, message: "Retry budget exhausted")
    }
}
