import SwiftUI
import UIKit

/// RA4 — unified Operator Status overlay.
///
/// Subtle pill below the safe area / Dynamic Island, visible only when
/// *something is wrong*. Sources:
///
/// - **Offline:** `NetworkMonitor.shared.isConnected == false`
/// - **Hot:** `ThermalMonitor.shared.isHot` (`.serious` / `.critical`)
/// - **Battery low:** `UIDevice.batteryLevel < 0.20` AND `batteryState != .charging`
/// - **Pending uploads:** `Booth360UploadQueue.shared.pendingCount > 0`
///
/// Zero problems → overlay hidden (no chrome). One → compact pill with
/// the most-severe label. Two+ → tap-to-expand list (BM3 follow-up could
/// add the expand; for now we show the most-severe + a "+N" count).
///
/// Mounted in `RootView` via `.overlay(alignment: .top)`. Respects Reduce
/// Motion via `@Environment(\.accessibilityReduceMotion)`.
struct StatusOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var batteryLevel: Float = UIDevice.current.batteryLevel
    @State private var batteryState: UIDevice.BatteryState = UIDevice.current.batteryState
    private let network = NetworkMonitor.shared
    private let thermal = ThermalMonitor.shared
    private let queue = Booth360UploadQueue.shared

    var body: some View {
        let alerts = activeAlerts
        if !alerts.isEmpty {
            pill(alerts: alerts)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .transition(
                    reduceMotion
                    ? .identity
                    : .move(edge: .top).combined(with: .opacity)
                )
                .animation(
                    reduceMotion ? nil : .easeInOut(duration: 0.25),
                    value: alerts.count
                )
                .onAppear { startBatteryMonitoring() }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)) { _ in
                    batteryLevel = UIDevice.current.batteryLevel
                }
                .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
                    batteryState = UIDevice.current.batteryState
                }
        } else {
            // Empty overlay still wires battery monitoring so the system fires
            // notifications even before the first alert. Cheap.
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear { startBatteryMonitoring() }
        }
    }

    // MARK: - Composition

    private func pill(alerts: [Alert]) -> some View {
        let primary = alerts[0]
        let extras = max(0, alerts.count - 1)
        return HStack(spacing: 8) {
            Image(systemName: primary.symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(primary.tint)
            Text(primary.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
            if extras > 0 {
                Text("+\(extras)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.18), in: Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule().stroke(primary.tint.opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary(alerts: alerts))
    }

    private func accessibilitySummary(alerts: [Alert]) -> String {
        alerts.map(\.label).joined(separator: ", ")
    }

    // MARK: - Alert collection (severity-ordered)

    private var activeAlerts: [Alert] {
        var out: [Alert] = []
        if !network.isConnected {
            out.append(Alert(kind: .offline,
                             label: "Offline",
                             symbol: "wifi.slash",
                             tint: BoothifyTheme.warning))
        }
        switch thermal.thermalState {
        case .critical:
            out.append(Alert(kind: .thermalCritical,
                             label: "Device too hot",
                             symbol: "thermometer.high",
                             tint: BoothifyTheme.error))
        case .serious:
            out.append(Alert(kind: .thermalSerious,
                             label: "Device warming up",
                             symbol: "thermometer.medium",
                             tint: BoothifyTheme.warning))
        default: break
        }
        if isBatteryLow {
            let pct = max(0, Int(batteryLevel * 100))
            out.append(Alert(kind: .batteryLow,
                             label: "Battery \(pct)%",
                             symbol: "battery.25",
                             tint: BoothifyTheme.error))
        }
        let pending = queue.pendingCount
        if pending > 0 {
            out.append(Alert(kind: .pendingUploads,
                             label: "\(pending) upload\(pending == 1 ? "" : "s") pending",
                             symbol: "icloud.and.arrow.up",
                             tint: BoothifyTheme.violet))
        }
        return out
    }

    /// Considered low when <20% AND not charging. iOS reports `batteryLevel
    /// = -1` when monitoring is disabled, so guard against that too.
    private var isBatteryLow: Bool {
        guard batteryLevel >= 0 else { return false }
        if batteryState == .charging || batteryState == .full { return false }
        return batteryLevel < 0.20
    }

    private func startBatteryMonitoring() {
        // Idempotent. iOS ignores re-enables.
        UIDevice.current.isBatteryMonitoringEnabled = true
        // Initial state needs an explicit refresh — notifications only fire
        // on CHANGES after this point.
        batteryLevel = UIDevice.current.batteryLevel
        batteryState = UIDevice.current.batteryState
    }

    // MARK: - Alert model

    private struct Alert: Equatable {
        enum Kind: String { case offline, thermalSerious, thermalCritical, batteryLow, pendingUploads }
        let kind: Kind
        let label: String
        let symbol: String
        let tint: Color
    }
}
