import Foundation

/// Phase 8 — the perf-budget estimator (blueprint §8): given device class +
/// template complexity, predict whether the render lands inside the guest
/// handoff window and warn the operator BEFORE the event, not mid-guest.
/// Heuristic by design — thresholds are configurable constants the human can
/// recalibrate on real hardware (L3 → HANDOFF).
enum PerfBudget {
    enum Verdict: Equatable {
        case fits
        case tight(reason: String)
        case tooHeavy(reason: String)

        var operatorMessage: String? {
            switch self {
            case .fits: return nil
            case .tight(let reason): return "Renders may run long on this device — \(reason). Consider Fast Share or a lighter template."
            case .tooHeavy(let reason): return "This combo will likely miss the guest handoff window — \(reason). Switch to a lighter template or Fast Share."
            }
        }
    }

    /// Relative device performance score. Coarse by intent: model identifiers
    /// map to generations; unknown/newer → generous score (fail open — a NEW
    /// device must never warn).
    static func deviceScore(modelIdentifier: String) -> Double {
        // Parse the MAJOR model number ("iPhone11,8" → family iPhone, major 11)
        // — naive prefix matching would tag a future "iPhone99" as weak.
        func major(after family: String) -> Int? {
            guard modelIdentifier.hasPrefix(family) else { return nil }
            let digits = modelIdentifier.dropFirst(family.count).prefix { $0.isNumber }
            return Int(digits)
        }
        if let m = major(after: "iPhone") {
            if m <= 11 { return 0.5 }   // ≤ XS/XR era
            if m <= 13 { return 1.0 }   // 12-series era
            return 1.6
        }
        if let m = major(after: "iPad") {
            if m <= 8 { return 0.5 }
            if m <= 13 { return 1.0 }
            return 1.6
        }
        return 1.6   // unknown family — fail open, never warn a device we don't know
    }

    /// Estimated render cost in "seconds of work per second of clip".
    static func templateCost(
        template: MotionTemplate,
        preset: RenderSpec.Preset,
        hasOverlay: Bool,
        hasIntroOutro: Bool
    ) -> Double {
        var cost = 1.0
        if template == .reverseBounce { cost *= 2.0 }   // reverse re-encode doubles work (§7.3)
        if hasOverlay { cost *= 1.2 }                    // per-frame CI compositing
        if hasIntroOutro { cost *= 1.15 }
        if preset == .bestQuality { cost *= 1.25 }
        return cost
    }

    /// Handoff window target: render should complete within ~3× clip length
    /// on the device (guest is still at the booth); >6× misses the window.
    static func verdict(
        deviceScore: Double,
        templateCost: Double
    ) -> Verdict {
        let workFactor = templateCost / max(deviceScore, 0.1)
        if workFactor <= 3.0 { return .fits }
        if workFactor <= 6.0 {
            return .tight(reason: "estimated \(String(format: "%.1f", workFactor))× realtime")
        }
        return .tooHeavy(reason: "estimated \(String(format: "%.1f", workFactor))× realtime")
    }

    /// One-call operator verdict for the current device + event settings.
    static func evaluate(settings: EventSettings) -> Verdict {
        let template = MotionTemplate(rawValue: settings.ai360.motionTemplate ?? "") ?? .heroSlow
        let preset = RenderSpec.Preset(rawValue: settings.ai360.exportPreset ?? "") ?? .fastShare
        let cost = templateCost(
            template: template,
            preset: preset,
            hasOverlay: settings.brandOverlay.enabled,
            hasIntroOutro: settings.ai360.introRelativePath != nil || settings.ai360.outroRelativePath != nil
        )
        return verdict(deviceScore: deviceScore(modelIdentifier: currentModelIdentifier()), templateCost: cost)
    }

    static func currentModelIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
