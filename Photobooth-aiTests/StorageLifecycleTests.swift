import XCTest
@testable import Photobooth_ai

/// Phase 2 gate: the purge policy is unit-tested (blueprint Phase 2 Gate A).
final class StorageLifecycleTests: XCTestCase {

    private var tempRoot: URL!
    private var storage: StorageLifecycle!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-tests-\(UUID().uuidString)", isDirectory: true)
        storage = StorageLifecycle(root: tempRoot, masterCapPerEvent: 3)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    /// Write a dummy file with a controlled modification date.
    private func touch(_ url: URL, ageSeconds: TimeInterval) throws {
        try Data("x".utf8).write(to: url)
        let date = Date(timeIntervalSinceNow: -ageSeconds)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    func testPurgeRawRemovesFileAndToleratesMissing() throws {
        let jobId = UUID()
        storage.prepare(eventId: UUID())
        let raw = storage.rawCaptureURL(jobId: jobId)
        try touch(raw, ageSeconds: 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))

        storage.purgeRaw(jobId: jobId)
        XCTAssertFalse(FileManager.default.fileExists(atPath: raw.path))

        // Second purge of the same id must be a safe no-op (no crash).
        storage.purgeRaw(jobId: jobId)
    }

    func testMasterCapKeepsNewestAndPurgesOldest() throws {
        let eventId = UUID()
        storage.prepare(eventId: eventId)
        var ids: [UUID] = []
        // 5 masters, oldest first (ages 50,40,30,20,10s) — cap is 3.
        for i in 0..<5 {
            let id = UUID()
            ids.append(id)
            try touch(storage.masterURL(eventId: eventId, jobId: id), ageSeconds: TimeInterval(50 - i * 10))
        }

        let removed = storage.enforceMasterCap(eventId: eventId)
        XCTAssertEqual(removed, 2, "cap 3 over 5 files must purge exactly the 2 oldest")

        let fm = FileManager.default
        // The two oldest (ids[0], ids[1]) are gone; the three newest survive.
        XCTAssertFalse(fm.fileExists(atPath: storage.masterURL(eventId: eventId, jobId: ids[0]).path))
        XCTAssertFalse(fm.fileExists(atPath: storage.masterURL(eventId: eventId, jobId: ids[1]).path))
        for id in ids.suffix(3) {
            XCTAssertTrue(fm.fileExists(atPath: storage.masterURL(eventId: eventId, jobId: id).path))
        }
    }

    func testLowStoragePurgeRemovesRawsFirstAndHalvesMasters() throws {
        let eventId = UUID()
        storage.prepare(eventId: eventId)
        // 2 raws + 3 masters (cap 3 → low-storage keeps max(1, 3/2)=1 master)
        try touch(storage.rawCaptureURL(jobId: UUID()), ageSeconds: 5)
        try touch(storage.rawCaptureURL(jobId: UUID()), ageSeconds: 6)
        for age in [30.0, 20.0, 10.0] {
            try touch(storage.masterURL(eventId: eventId, jobId: UUID()), ageSeconds: age)
        }

        let removed = storage.purgeForLowStorage()
        XCTAssertEqual(removed, 2 + 2, "2 raws + 2 of 3 masters must go")

        let rawLeft = try FileManager.default.contentsOfDirectory(atPath: storage.rawDirectory.path)
        XCTAssertTrue(rawLeft.isEmpty)
        let mastersLeft = try FileManager.default.contentsOfDirectory(atPath: storage.mastersDirectory(eventId: eventId).path)
        XCTAssertEqual(mastersLeft.count, 1, "half the cap (min 1) survives")
    }

    func testIsStorageLowFailsSafeAndDetectsRealVolume() {
        // Real volume has far more than 1 byte free → not low.
        XCTAssertFalse(storage.isStorageLow(threshold: 1))
        // Absurdly high threshold → low (proves the comparison direction).
        XCTAssertTrue(storage.isStorageLow(threshold: .max))
    }
}
