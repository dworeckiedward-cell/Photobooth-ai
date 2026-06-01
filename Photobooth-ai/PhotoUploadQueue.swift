import Foundation
import os.log

/// Offline photo upload queue.
///
/// When a guest picks a style and the device has no network, the captured
/// photo + metadata are stored locally here. On the next network restore
/// (or app launch), `replayPending(app:)` replays all queued jobs.
///
/// Each job's image bytes live at:
///   Application Support/photo-queue/{id}.jpg
///
/// The job manifest lives at:
///   Application Support/photo-upload-queue.json
///
/// Max 5 retry attempts per job; after that the job is logged and discarded.
@MainActor
final class PhotoUploadQueue {
    static let shared = PhotoUploadQueue()

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "PhotoUploadQueue")

    private var pending: [PendingPhotoJob] = []

    private static let maxRetries = 5

    private init() {
        load()
    }

    // MARK: - Public API

    var pendingCount: Int { pending.count }

    func enqueue(job: PendingPhotoJob) {
        guard !pending.contains(where: { $0.id == job.id }) else { return }
        // Persist image data to disk before adding to manifest.
        saveImageData(job.imageData, id: job.id)
        pending.append(job)
        saveManifest()
        log.info("enqueued photo job \(job.id.uuidString, privacy: .public) for event \(job.eventId.uuidString, privacy: .public)")
    }

    func remove(id: UUID) {
        pending.removeAll { $0.id == id }
        deleteImageFile(id: id)
        saveManifest()
        log.debug("removed photo job \(id.uuidString, privacy: .public)")
    }

    /// Called on app launch and on network restore. Replays all pending jobs.
    /// Each job is attempted once per call; retryCount is incremented on failure.
    /// Jobs that exceed maxRetries are dropped.
    func replayPending(app: AppState) {
        guard !pending.isEmpty else { return }
        log.info("replaying \(self.pending.count, privacy: .public) pending photo job(s)")

        // Capture snapshot; mutations happen inside the Task.
        let snapshot = pending

        Task {
            for job in snapshot {
                // Check image file still exists — drop ghost entries.
                guard FileManager.default.fileExists(atPath: imageFileURL(id: job.id).path) else {
                    log.warning("image file missing for job \(job.id.uuidString, privacy: .public) — dropping")
                    remove(id: job.id)
                    continue
                }

                // Exceeded retry cap — discard.
                if job.retryCount >= PhotoUploadQueue.maxRetries {
                    log.error("job \(job.id.uuidString, privacy: .public) exceeded max retries — discarding")
                    remove(id: job.id)
                    continue
                }

                do {
                    let imageData = try Data(contentsOf: imageFileURL(id: job.id))

                    // 1. Upload source photo.
                    let photoId = try await BoothifyAPI.shared.uploadPhoto(
                        imageData: imageData,
                        eventId: job.eventId,
                        style: job.style
                    )

                    // 2. Fire generation — fire-and-forget; ResultView polls.
                    Task.detached { [photoId, style = job.style] in
                        do {
                            _ = try await BoothifyAPI.shared.generatePhoto(photoId: photoId, style: style)
                        } catch {
                            // Generation errors surface through the polling response.
                        }
                    }

                    // 3. Navigate to result and remove from queue.
                    app.push(.result(eventId: job.eventId, photoId: photoId))
                    remove(id: job.id)
                    log.info("replayed job \(job.id.uuidString, privacy: .public) → photoId \(photoId.uuidString, privacy: .public)")
                } catch {
                    // Increment retry count.
                    if let idx = pending.firstIndex(where: { $0.id == job.id }) {
                        pending[idx].retryCount += 1
                        saveManifest()
                        log.warning("replay failed for job \(job.id.uuidString, privacy: .public) (attempt \(self.pending[idx].retryCount, privacy: .public)): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    // MARK: - Persistence — manifest

    private var manifestURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("photo-upload-queue.json", isDirectory: false)
    }

    private var imageDirectoryURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("photo-queue", isDirectory: true)
    }

    private func imageFileURL(id: UUID) -> URL {
        imageDirectoryURL.appendingPathComponent("\(id.uuidString).jpg", isDirectory: false)
    }

    private func saveManifest() {
        do {
            // Strip imageData before writing manifest — data lives in per-file JPEGs.
            let stripped = pending.map { PendingPhotoJob(
                id: $0.id,
                eventId: $0.eventId,
                style: $0.style,
                imageData: Data(), // not stored in manifest
                createdAt: $0.createdAt,
                retryCount: $0.retryCount
            ) }
            let data = try JSONEncoder().encode(stripped)
            try FileManager.default.createDirectory(
                at: manifestURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            log.error("saveManifest failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: manifestURL.path),
              let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([PendingPhotoJob].self, from: data) else {
            return
        }
        pending = decoded
        log.info("loaded \(self.pending.count, privacy: .public) pending photo job(s) from disk")
    }

    // MARK: - Persistence — image files

    private func saveImageData(_ data: Data, id: UUID) {
        do {
            try FileManager.default.createDirectory(
                at: imageDirectoryURL,
                withIntermediateDirectories: true
            )
            try data.write(to: imageFileURL(id: id), options: .atomic)
        } catch {
            log.error("saveImageData failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func deleteImageFile(id: UUID) {
        let url = imageFileURL(id: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            log.error("deleteImageFile failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
}

// MARK: - PendingPhotoJob

struct PendingPhotoJob: Codable {
    let id: UUID
    let eventId: UUID
    let style: PhotoStyle
    let imageData: Data   // empty in the manifest; loaded from disk on replay
    let createdAt: Date
    var retryCount: Int = 0

    init(id: UUID, eventId: UUID, style: PhotoStyle, imageData: Data, createdAt: Date, retryCount: Int = 0) {
        self.id = id
        self.eventId = eventId
        self.style = style
        self.imageData = imageData
        self.createdAt = createdAt
        self.retryCount = retryCount
    }
}
