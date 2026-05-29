import Foundation
import Network
import os.log

/// RA4 — observable connectivity flag.
///
/// `NWPathMonitor` is the modern way to know the device's reachability
/// without resolving a specific host. We expose `isConnected` and stamp
/// the most recent transition so the HUD can decide whether to show /
/// auto-hide an "Offline" pill.
@MainActor
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var lastChangedAt: Date = .now

    private let log = Logger(subsystem: "com.servify.Photobooth-ai", category: "Network")
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "boothify.network-monitor")

    private init() {
        startObserving()
    }

    private func startObserving() {
        monitor.pathUpdateHandler = { [weak self] path in
            // Hop back to MainActor — observable state mutation requires it.
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.apply(connected: connected)
            }
        }
        monitor.start(queue: queue)
    }

    private func apply(connected: Bool) {
        guard connected != isConnected else { return }
        log.notice("network: \(self.isConnected ? "online" : "offline") → \(connected ? "online" : "offline")")
        isConnected = connected
        lastChangedAt = .now
    }
}
