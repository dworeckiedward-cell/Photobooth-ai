import XCTest
@testable import Photobooth_ai

/// Characterization: the EventSettings decoder is section-tolerant.
/// Each section decodes with `try? … ?? default`, so garbage/partial sections
/// fall back to defaults and unknown keys are ignored. These tests freeze that
/// behavior BEFORE the Phase-1 model cut: after AI sections are removed from
/// the model, `legacyBlobWithAIKeys` must STILL decode (the AI keys simply
/// become unknown keys). If these tests break, old operators' stored settings
/// would stop decoding — that's a data-loss regression, not a refactor detail.
final class EventSettingsDecodeTests: XCTestCase {

    /// A stored blob shaped like a pre-360-pivot save: AI sections present
    /// (with partial/garbage bodies), plus an unknown future key.
    private let legacyBlobWithAIKeys = Data("""
    {
      "aiPortraits": {"legacyField": "blob"},
      "effects": {"someOldKnob": 1},
      "stickers": {"v": 2},
      "capture": {"partialGarbage": true},
      "unknownTopLevelKey": {"y": 2}
    }
    """.utf8)

    func testEmptyObjectDecodesToDefaults() throws {
        let decoded = try JSONDecoder().decode(EventSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, EventSettings.default)
    }

    func testLegacyBlobWithAIKeysStillDecodes() throws {
        // Must not throw today, and must not throw after the AI-field cut.
        let decoded = try JSONDecoder().decode(EventSettings.self, from: legacyBlobWithAIKeys)
        // Garbage sections fall back to defaults rather than corrupting state.
        XCTAssertEqual(decoded.capture, EventSettings.default.capture)
    }

    func testRoundTripPreservesValues() throws {
        var s = EventSettings.default
        s.survey.enabled = true
        s.survey.questionText = "ROUND-TRIP-GUARD"
        s.disclaimer.disclaimerText = "ROUND-TRIP-DISCLAIMER"
        s.lockPin.enabled = true

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(EventSettings.self, from: data)

        XCTAssertTrue(decoded.survey.enabled)
        XCTAssertEqual(decoded.survey.questionText, "ROUND-TRIP-GUARD")
        XCTAssertEqual(decoded.disclaimer.disclaimerText, "ROUND-TRIP-DISCLAIMER")
        XCTAssertTrue(decoded.lockPin.enabled)
    }
}
