import Foundation

/// Phase 8 — trigger choreography (blueprint §7.9). Trigger↔capture timing is
/// a top operator pain: the hero must not start early/late. The STATE MACHINE
/// is pure and unit-tested; physical inputs (arm motion, Bluetooth buttons)
/// feed events into it. Bluetooth is a v2-verified layer — the protocol seam
/// exists, pairing goes to HANDOFF.
enum TriggerType: String, CaseIterable, Identifiable, Sendable {
    case manual        // operator/guest taps the record button
    case timer         // countdown starts on tap, capture follows
    case motionStart   // capture starts when the arm starts spinning
    case bluetooth     // v2: spinner-brand integrations (stubbed)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .manual:      "Manual"
        case .timer:       "Countdown"
        case .motionStart: "Start on spin"
        case .bluetooth:   "Bluetooth spinner"
        }
    }

    var isV2Locked: Bool { self == .bluetooth }
}

/// Pure trigger state machine.
struct TriggerStateMachine: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case idle
        /// Waiting for the trigger condition (motion / BT signal).
        case armed
        /// Countdown running (timer trigger, or post-trigger choreography).
        case countdown(remaining: Int)
        case recording
        case finished
    }

    enum Event: Equatable, Sendable {
        case arm
        case tap                       // manual start/stop
        case motionDetected(magnitude: Double)
        case bluetoothStart            // v2
        case countdownTick
        case recordingComplete
        case reset
    }

    /// Side effects the host view must perform on a transition.
    enum Effect: Equatable, Sendable {
        case beginCountdown(seconds: Int)
        case startCapture
        case stopCapture
        case none
    }

    let type: TriggerType
    /// Motion magnitude (0…1) that counts as "the arm is spinning".
    /// Tunable per rig (blueprint: choreography must be tunable).
    var motionThreshold: Double = 0.3
    var countdownSeconds: Int = 3
    private(set) var state: State = .idle

    mutating func handle(_ event: Event) -> Effect {
        switch (state, event) {
        case (_, .reset):
            state = .idle
            return .none

        case (.idle, .arm):
            state = .armed
            // Timer trigger starts its countdown the moment it's armed.
            if type == .timer {
                state = .countdown(remaining: countdownSeconds)
                return .beginCountdown(seconds: countdownSeconds)
            }
            return .none

        case (.armed, .tap) where type == .manual:
            state = .recording
            return .startCapture

        case (.armed, .motionDetected(let magnitude)) where type == .motionStart:
            guard magnitude >= motionThreshold else { return .none }
            // Arm is moving — short sync countdown so the guest is ready and
            // the hero lands mid-spin, not on the wobble-up.
            state = .countdown(remaining: 1)
            return .beginCountdown(seconds: 1)

        case (.armed, .bluetoothStart) where type == .bluetooth:
            state = .recording
            return .startCapture

        case (.countdown(let remaining), .countdownTick):
            if remaining <= 1 {
                state = .recording
                return .startCapture
            }
            state = .countdown(remaining: remaining - 1)
            return .none

        case (.recording, .tap) where type == .manual:
            state = .finished
            return .stopCapture

        case (.recording, .recordingComplete):
            state = .finished
            return .none

        default:
            return .none   // illegal/ignored transitions never crash a booth
        }
    }
}

/// v2 seam: a spinner-brand adapter feeds `.bluetoothStart` (and speed data)
/// into the machine. Stub only — physical pairing is NEEDS-DEVICE/HANDOFF.
protocol BluetoothSpinnerAdapter {
    var onStartSignal: (() -> Void)? { get set }
    func startScanning()
    func stopScanning()
}
