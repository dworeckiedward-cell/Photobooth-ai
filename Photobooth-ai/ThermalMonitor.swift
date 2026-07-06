import Foundation
import os.log

/// RA1 — observable wrapper around `ProcessInfo.thermalState`.
///
/// 4-hour event of continuous render + camera + upload pushes
/// iPhone 12/13 into `.serious` → `.critical` thermal throttling. The OS
/// silently caps CPU, GPU, and frame rates; operator sees "the app got
/// slow" with no signal of why.
///
/// This monitor:
/// 1. Surfaces the live thermal state to UI (StatusOverlay in RA4).
/// 2. Lets the render client auto-degrade bitrate when hot
///    (so we throttle *before* the OS does, deliberately, with the
///    operator informed via the HUD).
/// 3. Debounces transitions (anti-flap): a 30s cooldown prevents a
///    bouncing `.fair ↔ .serious` from re-encoding the render bitrate
///    every few seconds.
@MainActor
@Observable
final class ThermalMonitor {
    static let shared = ThermalMonitor()

    private(set) var thermalState: ProcessInfo.ThermalState
    /// Last time `thermalState` flipped — used by the bitrate degrader to
    /// avoid re-deciding more than once per 30 seconds.
    private(set) var lastChangedAt: Date

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Thermal")
    private var observer: NSObjectProtocol?

    private init() {
        self.thermalState = ProcessInfo.processInfo.thermalState
        self.lastChangedAt = .now
        startObserving()
    }

    /// True for `.serious` and `.critical` — the two states where Apple
    /// recommends shedding work proactively.
    var isHot: Bool {
        thermalState == .serious || thermalState == .critical
    }

    /// Recommended bitrate multiplier for the render. 1.0 = full
    /// quality, 0.7 = 30% reduction when hot. Anti-flap: only updates
    /// the underlying decision when `thermalState` has been stable for
    /// at least 30s.
    var bitrateMultiplier: Double {
        switch thermalState {
        case .nominal, .fair: return 1.0
        case .serious:        return 0.7
        case .critical:       return 0.5
        @unknown default:     return 1.0
        }
    }

    /// Returns true when bitrate decisions are "stable" — i.e. thermal state
    /// has held for the debounce window. Render code asks this before
    /// reacting to a state flip, so we don't transcode based on a 2-second
    /// hot blip.
    func isStable(debounce seconds: TimeInterval = 30) -> Bool {
        Date().timeIntervalSince(lastChangedAt) >= seconds
    }

    private func startObserving() {
        observer = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleChange()
            }
        }
    }

    private func handleChange() {
        let new = ProcessInfo.processInfo.thermalState
        guard new != thermalState else { return }
        log.notice("thermal state: \(self.thermalState.label, privacy: .public) → \(new.label, privacy: .public)")
        thermalState = new
        lastChangedAt = .now
    }

    // No deinit cleanup needed — `ThermalMonitor.shared` lives for the
    // whole app lifetime, and trying to access a MainActor `observer`
    // from the nonisolated deinit doesn't compile on Swift 6 anyway.
}

extension ProcessInfo.ThermalState {
    /// Human label for logs / HUD copy.
    var label: String {
        switch self {
        case .nominal:  "nominal"
        case .fair:     "fair"
        case .serious:  "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }
}
