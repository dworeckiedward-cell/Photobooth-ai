import Foundation
import os.log

/// BM1 — persistent pending-upload queue.
///
/// When `Booth360CloudUploader` fails (no WiFi at the event, backend hiccup)
/// the job lands here. The queue is just a JSON list of job ids backed by a
/// file in `Application Support/` — small, atomic, survives app kills.
///
/// On app launch (`AppState.bootstrapAuth`) we call `replayPending(app:)`
/// which re-enqueues every job with status `.failed` whose local file is
/// still on disk. Manual "Send again" buttons in the UI call `retry(jobId:)`
/// for a single job.
///
/// Idempotency lives in `BoothifyAPI` (backend keys by `client_job_id`), so
/// the queue can re-fire freely without making duplicate cloud rows.
@MainActor
final class Booth360UploadQueue {
    static let shared = Booth360UploadQueue()

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Booth360UploadQueue")

    /// Persistent list of failed job ids — written through to disk on every change.
    private var pendingJobIds: Set<UUID> = []

    private init() {
        load()
    }

    /// Add a job to the queue. Safe to call repeatedly — Set dedupes.
    /// `app` is unused right now but the signature keeps the future option
    /// of also persisting a snapshot of the Booth360Job state alongside.
    func enqueue(jobId: UUID, app _: AppState) {
        if pendingJobIds.insert(jobId).inserted {
            save()
            log.debug("queued \(jobId.uuidString, privacy: .public) for retry")
        }
    }

    /// Drop a job from the queue (called on successful upload).
    func remove(jobId: UUID) {
        if pendingJobIds.remove(jobId) != nil {
            save()
        }
    }

    /// Manual retry — operator tapped "Send again".
    func retry(jobId: UUID, app: AppState) {
        guard app.job(id: jobId) != nil else {
            log.warning("retry asked for missing job \(jobId.uuidString, privacy: .public)")
            return
        }
        Booth360CloudUploader.shared.enqueue(jobId: jobId, app: app)
    }

    /// Auto-retry at app launch. Re-fires every queued job whose local
    /// file still exists; drops the rest as dead. Non-blocking; uploads
    /// race in the background via Booth360CloudUploader.
    func replayPending(app: AppState) {
        let toRetry = pendingJobIds
        for jobId in toRetry {
            guard let job = app.job(id: jobId),
                  let url = job.finalVideoURL,
                  FileManager.default.fileExists(atPath: url.path) else {
                pendingJobIds.remove(jobId)
                continue
            }
            log.info("replaying queued upload for \(jobId.uuidString, privacy: .public)")
            Booth360CloudUploader.shared.enqueue(jobId: jobId, app: app)
        }
        save()
    }

    /// Current count for UI badges (e.g. "3 pending" on Event hub).
    var pendingCount: Int { pendingJobIds.count }

    var pendingIds: [UUID] { Array(pendingJobIds) }

    // MARK: - Persistence

    private var fileURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("booth360-pending-uploads.json", isDirectory: false)
    }

    private func save() {
        do {
            let array = pendingJobIds.map { $0.uuidString }
            let data = try JSONSerialization.data(withJSONObject: array)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            log.error("save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            return
        }
        pendingJobIds = Set(array.compactMap(UUID.init(uuidString:)))
    }
}
