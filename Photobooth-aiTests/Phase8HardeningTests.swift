import XCTest
@testable import Photobooth_ai

/// PHASE 8 GATE A: trigger state machine, tier gating (sandbox-safe),
/// perf-budget estimator, crash-recovery marker round-trip.
final class Phase8HardeningTests: XCTestCase {

    // MARK: - Trigger state machine

    func testManualTriggerFlow() {
        var machine = TriggerStateMachine(type: .manual)
        XCTAssertEqual(machine.handle(.arm), .none)
        XCTAssertEqual(machine.state, .armed)
        XCTAssertEqual(machine.handle(.tap), .startCapture)
        XCTAssertEqual(machine.state, .recording)
        XCTAssertEqual(machine.handle(.tap), .stopCapture)
        XCTAssertEqual(machine.state, .finished)
    }

    func testTimerTriggerCountsDownThenCaptures() {
        var machine = TriggerStateMachine(type: .timer, countdownSeconds: 3)
        XCTAssertEqual(machine.handle(.arm), .beginCountdown(seconds: 3))
        XCTAssertEqual(machine.handle(.countdownTick), .none)   // 3 → 2
        XCTAssertEqual(machine.handle(.countdownTick), .none)   // 2 → 1
        XCTAssertEqual(machine.handle(.countdownTick), .startCapture)
        XCTAssertEqual(machine.state, .recording)
    }

    func testMotionTriggerRespectsThresholdAndSyncs() {
        var machine = TriggerStateMachine(type: .motionStart, motionThreshold: 0.3)
        _ = machine.handle(.arm)
        // Sub-threshold wobble must NOT start the take (hero would land early).
        XCTAssertEqual(machine.handle(.motionDetected(magnitude: 0.1)), .none)
        XCTAssertEqual(machine.state, .armed)
        // Real spin → 1s sync countdown, then capture.
        XCTAssertEqual(machine.handle(.motionDetected(magnitude: 0.6)), .beginCountdown(seconds: 1))
        XCTAssertEqual(machine.handle(.countdownTick), .startCapture)
    }

    func testIllegalTransitionsAreIgnoredNotFatal() {
        var machine = TriggerStateMachine(type: .manual)
        XCTAssertEqual(machine.handle(.countdownTick), .none)   // tick while idle
        XCTAssertEqual(machine.handle(.tap), .none)             // tap while idle (not armed)
        XCTAssertEqual(machine.state, .idle)
        _ = machine.handle(.arm)
        XCTAssertEqual(machine.handle(.bluetoothStart), .none, "BT event on a manual trigger is ignored")
        XCTAssertEqual(machine.handle(.reset), .none)
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Tier gating (Decision 2 — sandbox-safe)

    func testGatingIsOpenWhenStoreHasNoProducts() {
        // "Never ship a build that locks because products are absent."
        for feature: PremiumFeature in [.watermarkRemoval, .allMotionTemplates, .customOverlays, .whiteLabel] {
            XCTAssertTrue(PremiumFeature.allowed(feature, tier: .free, storeConfigured: false))
        }
    }

    func testGatingActivatesOnceStoreIsConfigured() {
        XCTAssertFalse(PremiumFeature.allowed(.watermarkRemoval, tier: .free, storeConfigured: true))
        XCTAssertFalse(PremiumFeature.allowed(.allMotionTemplates, tier: .free, storeConfigured: true))
        XCTAssertTrue(PremiumFeature.allowed(.watermarkRemoval, tier: .pro, storeConfigured: true))
        XCTAssertTrue(PremiumFeature.allowed(.allMotionTemplates, tier: .pro, storeConfigured: true))
        XCTAssertFalse(PremiumFeature.allowed(.whiteLabel, tier: .pro, storeConfigured: true),
                       "white-label is Business")
        XCTAssertTrue(PremiumFeature.allowed(.multiDevice, tier: .business, storeConfigured: true))
    }

    // MARK: - Perf budget

    func testPerfBudgetWarnsOldDeviceHeavyTemplate() {
        let oldDevice = PerfBudget.deviceScore(modelIdentifier: "iPhone11,8") // XR
        let heavy = PerfBudget.templateCost(
            template: .reverseBounce, preset: .bestQuality, hasOverlay: true, hasIntroOutro: true
        )
        let verdict = PerfBudget.verdict(deviceScore: oldDevice, templateCost: heavy)
        guard case .tooHeavy = verdict else {
            return XCTFail("XR + reverse+best+overlay+bumpers must warn, got \(verdict)")
        }
        XCTAssertNotNil(verdict.operatorMessage)
    }

    func testPerfBudgetPassesNewDeviceLightTemplate() {
        let newDevice = PerfBudget.deviceScore(modelIdentifier: "iPhone18,2")
        let light = PerfBudget.templateCost(
            template: .heroSlow, preset: .fastShare, hasOverlay: false, hasIntroOutro: false
        )
        XCTAssertEqual(PerfBudget.verdict(deviceScore: newDevice, templateCost: light), .fits)
    }

    func testUnknownDeviceFailsOpen() {
        XCTAssertGreaterThan(PerfBudget.deviceScore(modelIdentifier: "iPhone99,9"), 1.0,
                             "a device we've never heard of must not warn (fail open)")
    }

    // MARK: - Crash-recovery marker

    func testInterruptedRenderMarkerRoundTrip() {
        let jobId = UUID()
        CrashRestoreManager.setActiveRender(jobId)
        XCTAssertEqual(CrashRestoreManager.interruptedRenderId(), jobId)
        CrashRestoreManager.clearActiveRender()
        XCTAssertNil(CrashRestoreManager.interruptedRenderId())
    }
}
