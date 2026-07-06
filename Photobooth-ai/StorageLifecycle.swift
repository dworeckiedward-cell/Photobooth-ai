import Foundation
import os.log

/// Phase 2 — local media lifecycle (blueprint §8 "Storage lifecycle", Decision 6).
///
/// Policy:
/// - RAW captures live only until their render completes, then are purged.
/// - Rendered MASTERS are kept per event, newest-first, capped at
///   `masterCapPerEvent` (configurable); enforcement purges oldest first.
/// - Low-storage: callers check `isStorageLow()` before recording; purge order
///   is raws first, then oldest masters (`purgeForLowStorage`).
///
/// Layout (under Application Support, or an injected root in tests):
///   booth360/raw/{jobId}.mov
///   booth360/masters/{eventId}/{jobId}.mp4
///
/// Every operation is best-effort + logged — a failed purge must never crash
/// an event night.
struct StorageLifecycle {
    /// Default cap: how many rendered masters to retain per event.
    static let defaultMasterCapPerEvent = 50
    /// Consider storage "low" under 2 GB free — high-fps raws are hundreds of
    /// MB each; leave the OS breathing room.
    static let lowStorageThresholdBytes: Int64 = 2_000_000_000

    let root: URL
    var masterCapPerEvent: Int

    private static let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "StorageLifecycle")

    /// Production instance rooted in Application Support.
    static let shared = StorageLifecycle(
        root: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("booth360", isDirectory: true),
        masterCapPerEvent: defaultMasterCapPerEvent
    )

    init(root: URL, masterCapPerEvent: Int = StorageLifecycle.defaultMasterCapPerEvent) {
        self.root = root
        self.masterCapPerEvent = masterCapPerEvent
    }

    // MARK: - Canonical locations

    var rawDirectory: URL { root.appendingPathComponent("raw", isDirectory: true) }

    func rawCaptureURL(jobId: UUID) -> URL {
        rawDirectory.appendingPathComponent("\(jobId.uuidString).mov")
    }

    func mastersDirectory(eventId: UUID) -> URL {
        root.appendingPathComponent("masters", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
    }

    func masterURL(eventId: UUID, jobId: UUID) -> URL {
        mastersDirectory(eventId: eventId).appendingPathComponent("\(jobId.uuidString).mp4")
    }

    /// Create the directories; call before first write.
    func prepare(eventId: UUID) {
        let fm = FileManager.default
        try? fm.createDirectory(at: rawDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: mastersDirectory(eventId: eventId), withIntermediateDirectories: true)
    }

    // MARK: - Purge policy

    /// Raw capture is disposable the moment its render completes.
    func purgeRaw(jobId: UUID) {
        let url = rawCaptureURL(jobId: jobId)
        do {
            try FileManager.default.removeItem(at: url)
            Self.log.debug("purged raw \(jobId.uuidString, privacy: .public)")
        } catch CocoaError.fileNoSuchFile {
            // already gone — fine
        } catch {
            Self.log.warning("raw purge failed for \(jobId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Purge ALL raw captures (low-storage first responder).
    /// Returns the number of files removed.
    @discardableResult
    func purgeAllRaws() -> Int {
        purgeContents(of: rawDirectory, keepNewest: 0)
    }

    /// Enforce the per-event master cap: newest `masterCapPerEvent` survive,
    /// oldest are removed. Returns the number of files removed.
    @discardableResult
    func enforceMasterCap(eventId: UUID) -> Int {
        purgeContents(of: mastersDirectory(eventId: eventId), keepNewest: masterCapPerEvent)
    }

    /// Low-storage responder: raws first, then trim every event's masters to
    /// half the cap. Returns total files removed.
    @discardableResult
    func purgeForLowStorage() -> Int {
        var removed = purgeAllRaws()
        let mastersRoot = root.appendingPathComponent("masters", isDirectory: true)
        let fm = FileManager.default
        if let eventDirs = try? fm.contentsOfDirectory(at: mastersRoot, includingPropertiesForKeys: nil) {
            for dir in eventDirs {
                removed += purgeContents(of: dir, keepNewest: max(1, masterCapPerEvent / 2))
            }
        }
        Self.log.notice("low-storage purge removed \(removed) files")
        return removed
    }

    /// True when free space on the data volume is below the threshold.
    /// Fails SAFE (false) when the capacity query itself fails — a query error
    /// must not block recording; the writer will surface real disk errors.
    func isStorageLow(threshold: Int64 = StorageLifecycle.lowStorageThresholdBytes) -> Bool {
        do {
            let values = try root.deletingLastPathComponent()
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            guard let capacity = values.volumeAvailableCapacityForImportantUsage else { return false }
            return capacity < threshold
        } catch {
            Self.log.warning("capacity query failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Internals

    /// Remove the oldest files in `dir`, keeping the newest `keepNewest`.
    @discardableResult
    private func purgeContents(of dir: URL, keepNewest: Int) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return 0 }

        let dated: [(URL, Date)] = files.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return (url, date)
        }
        // Newest first; everything past the keep window goes.
        let doomed = dated.sorted { $0.1 > $1.1 }.dropFirst(keepNewest)
        var removed = 0
        for (url, _) in doomed {
            if (try? fm.removeItem(at: url)) != nil { removed += 1 }
        }
        return removed
    }
}
