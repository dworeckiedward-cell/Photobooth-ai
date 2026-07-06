import XCTest
@testable import Photobooth_ai

/// Characterization: the 360 upload queue's core semantics — enqueue is
/// idempotent (Set-backed), remove works, counts are accurate. The queue is
/// KEEP (Section 5 of the blueprint); Phase 7 extends it and must not regress
/// these basics.
///
/// Note: `Booth360UploadQueue.shared` is a file-backed singleton — tests clean
/// up their own ids so the on-disk manifest isn't polluted across runs.
/// (Constructing a second `AppState` inside the test host crashes the runner,
/// which is why `enqueue` no longer takes one — see the Phase 0 decision log.)
final class Booth360UploadQueueTests: XCTestCase {

    private var testIds: [UUID] = []

    override func tearDown() {
        for id in testIds { Booth360UploadQueue.shared.remove(jobId: id) }
        testIds = []
        super.tearDown()
    }

    func testEnqueueIsIdempotentAndRemoveWorks() {
        let queue = Booth360UploadQueue.shared
        let baseline = queue.pendingCount

        let a = UUID(), b = UUID()
        testIds = [a, b]

        queue.enqueue(jobId: a)
        queue.enqueue(jobId: a) // duplicate — must not double-count
        queue.enqueue(jobId: b)
        XCTAssertEqual(queue.pendingCount, baseline + 2)
        XCTAssertTrue(queue.pendingIds.contains(a))
        XCTAssertTrue(queue.pendingIds.contains(b))

        queue.remove(jobId: a)
        XCTAssertEqual(queue.pendingCount, baseline + 1)
        XCTAssertFalse(queue.pendingIds.contains(a))

        queue.remove(jobId: b)
        XCTAssertEqual(queue.pendingCount, baseline)
    }
}
