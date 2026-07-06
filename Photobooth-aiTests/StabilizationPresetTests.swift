import XCTest
import AVFoundation
@testable import Photobooth_ai

/// PHASE 6 GATE A: preset selection + crop-cost estimation + unavailable-mode
/// disabling + legacy migration.
final class StabilizationPresetTests: XCTestCase {

    func testPresetToAVModeMapping() {
        XCTAssertEqual(StabilizationPreset.off.avMode, .off)
        XCTAssertEqual(StabilizationPreset.standard.avMode, .standard)
        XCTAssertEqual(StabilizationPreset.cinematic.avMode, .cinematic)
        XCTAssertEqual(StabilizationPreset.cinematicExtended.avMode, .cinematicExtended)
    }

    func testCropCostMonotonicallyIncreasesWithSmoothing() {
        let costs = [StabilizationPreset.off, .standard, .cinematic, .cinematicExtended]
            .map(\.estimatedCropFraction)
        XCTAssertEqual(costs.first, 0, "Off must cost no crop")
        for (a, b) in zip(costs, costs.dropFirst()) {
            XCTAssertLessThan(a, b, "more smoothing must honestly cost more crop")
        }
        // Preview text exists exactly when there IS a crop to preview.
        XCTAssertNil(StabilizationPreset.off.cropPreviewText)
        XCTAssertEqual(StabilizationPreset.cinematic.cropPreviewText, "~20% tighter frame")
    }

    func testUnavailableModesAreExcluded() {
        // Device supporting only .standard:
        let some = StabilizationPreset.supportedPresets(supportedAVModes: [.standard])
        XCTAssertEqual(some, [.off, .standard])
        // Device supporting nothing (simulator): only Off — honest.
        XCTAssertEqual(StabilizationPreset.supportedPresets(supportedAVModes: []), [.off])
        // Even a device supporting cinematicExtended must NOT offer it in v1.
        let rich = StabilizationPreset.supportedPresets(
            supportedAVModes: [.standard, .cinematic, .cinematicExtended]
        )
        XCTAssertFalse(rich.contains(.cinematicExtended), "Extended is v2-locked")
        XCTAssertEqual(rich, [.off, .standard, .cinematic])
    }

    func testLegacyBoolMigration() {
        XCTAssertEqual(StabilizationPreset.migrated(fromLegacyEnabled: false), .off)
        XCTAssertEqual(StabilizationPreset.migrated(fromLegacyEnabled: true), .standard)
        XCTAssertEqual(StabilizationPreset.migrated(fromLegacyEnabled: nil), .standard)
    }

    func testEffectivePresetPrefersNewFieldOverLegacy() {
        var camera = CameraSettings.default
        camera.stabilizationEnabled = false          // legacy says OFF
        camera.stabilizationPreset = "cinematic"     // new field says cinematic
        XCTAssertEqual(StabilizationPreset.effective(from: camera), .cinematic,
                       "explicit new preset wins over the legacy bool")

        camera.stabilizationPreset = "not-a-preset"
        XCTAssertEqual(StabilizationPreset.effective(from: camera), .off,
                       "garbage raw value falls back to legacy migration")
    }
}
