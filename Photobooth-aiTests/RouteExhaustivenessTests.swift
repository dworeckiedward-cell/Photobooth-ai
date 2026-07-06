import XCTest
@testable import Photobooth_ai

/// Characterization: the full Route surface. `Route` has associated values so
/// it can't be CaseIterable — instead this test CONSTRUCTS every case. When
/// Phase 1 removes a case, this file stops compiling, forcing a conscious
/// update in the same change that edits RootView's destination switch (which
/// has no `default`, so the compiler enforces the other side).
final class RouteExhaustivenessTests: XCTestCase {

    func testAllRouteCasesAreConstructibleAndDistinct() {
        let e = UUID(), p = UUID(), j = UUID()
        let d = Data()

        let all: [Route] = [
            .photoboothLanding,
            .eventHub(eventId: e),
            .camera(eventId: e),
            .stylePicker(eventId: e, capturedImageData: d),
            .instantLooks(eventId: e, capturedImageData: d),
            .result(eventId: e, photoId: p),
            .gallery(eventId: e),
            .slideshow(eventId: e),
            .settingsHub(eventId: e),
            .settingsCapture(eventId: e),
            .settingsCamera(eventId: e),
            .settingsAIPortraits(eventId: e),
            .settingsAI360(eventId: e),
            .settingsEffects(eventId: e),
            .settingsSharing(eventId: e),
            .settingsEmailSMS(eventId: e),
            .settingsLockPin(eventId: e),
            .settingsGallerySlideshow(eventId: e),
            .settingsPrint(eventId: e),
            .settingsBackgroundRemoval(eventId: e),
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

        XCTAssertEqual(all.count, 34, "Route case count changed — update this test AND RootView's destination switch together.")
        XCTAssertEqual(Set(all).count, all.count, "Route cases must be distinct/hashable.")
    }
}
