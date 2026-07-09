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
        // Every key in the blob (aiPortraits/effects/stickers/capture/…) is now
        // an UNKNOWN key post-cut, so the whole thing falls back to defaults
        // rather than corrupting state — old operators' saves keep loading.
        XCTAssertEqual(decoded, EventSettings.default)
    }

    /// SECURITY characterization: the lock PIN must NEVER be encoded into
    /// the persisted settings blob (Keychain is the only store), but the
    /// decoder must still READ a legacy `pin` key so old plaintext blobs
    /// can be migrated. If this test breaks, PINs leak back to UserDefaults.
    func testLockPinIsNeverEncodedButLegacyPinStillDecodes() throws {
        var s = EventSettings.default
        s.lockPin.enabled = true
        s.lockPin.pin = "1234"

        let data = try JSONEncoder().encode(s)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("1234"), "PIN leaked into the encoded settings blob")

        // Round-trip: pin is gone (in-memory only), the rest survives.
        let decoded = try JSONDecoder().decode(EventSettings.self, from: data)
        XCTAssertTrue(decoded.lockPin.enabled)
        XCTAssertEqual(decoded.lockPin.pin, "")

        // Legacy blob WITH a plaintext pin still decodes (migration source).
        let legacy = Data(#"{"lockPin":{"enabled":true,"pin":"9876","idleTimeoutMinutes":5}}"#.utf8)
        let migrated = try JSONDecoder().decode(EventSettings.self, from: legacy)
        XCTAssertEqual(migrated.lockPin.pin, "9876")
        XCTAssertEqual(migrated.lockPin.idleTimeoutMinutes, 5)
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
