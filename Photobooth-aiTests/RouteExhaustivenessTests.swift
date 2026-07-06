import XCTest
@testable import Photobooth_ai

/// Characterization: the full Route surface (360-only after the Phase 1 cut).
/// `Route` has associated values so it can't be CaseIterable — instead this
/// test CONSTRUCTS every case. Removing a case breaks compilation here,
/// forcing a conscious update in the same change that edits RootView's
/// destination switch (which has no `default`, so the compiler enforces the
/// other side).
final class RouteExhaustivenessTests: XCTestCase {

    func testAllRouteCasesAreConstructibleAndDistinct() {
        let e = UUID(), j = UUID()

        let all: [Route] = [
            .settingsCamera(eventId: e),
            .settingsAI360(eventId: e),
            .settingsSharing(eventId: e),
            .settingsEmailSMS(eventId: e),
            .settingsLockPin(eventId: e),
            .settingsStickers(eventId: e),
            .settingsVirtualAttendant(eventId: e),
            .settingsDisclaimer(eventId: e),
            .settingsSurvey(eventId: e),
            .settingsSharingStatus(eventId: e),
            .settingsAccount(eventId: e),
            .settingsComingSoon(title: "t", blurb: "b"),
            .aboutBoothify,
            .booth360Landing,
            .booth360EventHub(eventId: e),
            .booth360Recording(eventId: e),
            .booth360Processing(jobId: j),
            .booth360Result(jobId: j),
            .settings360Hub(eventId: e),
        ]

        XCTAssertEqual(all.count, 19, "Route case count changed — update this test AND RootView's destination switch together.")
        XCTAssertEqual(Set(all).count, all.count, "Route cases must be distinct/hashable.")
    }
}
