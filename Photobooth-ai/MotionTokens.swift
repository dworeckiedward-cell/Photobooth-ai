import SwiftUI
import UIKit

/// RA5 — single source of truth for animation curves.
///
/// Before this file every view picked its own `.spring(…)`, `.easeOut(0.7)`,
/// or `.default` ad-hoc, so the same action (e.g. button press) felt
/// different on every screen. World-class iOS apps (Halide, Linear,
/// Procreate) publish 3–4 named curves and reuse them religiously —
/// the discipline is more important than the exact values.
///
/// Pick a token by intent, not by look:
///
/// - `BoothifyMotion.quickTap`   — tap feedback, button scales, short
///                                  state toggles. Snappy, almost no bounce.
/// - `BoothifyMotion.smoothFlow` — sheets, navigation transitions, layout
///                                  changes. Smooth, intentional.
/// - `BoothifyMotion.bouncy`     — success / "wow" moments (job done,
///                                  copy-link confirmed, photo revealed).
/// - `BoothifyMotion.gentle`     — neutral progress (loading bars, ring
///                                  fills, status pulses). Deliberately
///                                  ease-based, not springy.
///
/// All four respect the user's Reduce Motion setting through `animate(_:)`.
/// Direct uses (`withAnimation(BoothifyMotion.quickTap) { … }`) are fine
/// for one-shots but consider `BoothifyMotion.animate(.quickTap, …) { … }`
/// when running in a context where Reduce Motion matters.
enum BoothifyMotion {
    /// ~250ms spring, low bounce. For tap feedback, status toggles, badge
    /// scales. Should feel near-instant but with a hint of physicality.
    static let quickTap = Animation.spring(response: 0.25, dampingFraction: 0.85)

    /// ~450ms spring, low bounce. For view transitions, sheet enter/exit,
    /// layout reflows. Reads as intentional motion, not "snappy".
    static let smoothFlow = Animation.spring(response: 0.45, dampingFraction: 0.85)

    /// ~550ms spring, deliberate overshoot. For success states + "wow"
    /// moments (cloud upload confirmed, photo reveal, copy-link flashing
    /// to "Copied"). Reserve for celebration; overuse cheapens.
    static let bouncy = Animation.spring(response: 0.55, dampingFraction: 0.65)

    /// 300ms ease-in-out. For progress bars, ring fills, status pulses —
    /// anywhere a spring would feel manipulative. Neutral by design.
    static let gentle = Animation.easeInOut(duration: 0.3)

    /// Reduce-Motion-aware wrapper. Prefer this over bare
    /// `withAnimation(BoothifyMotion.x)` in views that mutate state in
    /// response to a user action — the alternative is sprinkling
    /// `@Environment(\.accessibilityReduceMotion)` checks everywhere.
    ///
    /// When `Reduce Motion` is ON, runs `body` with animation disabled
    /// (snap to final state). When OFF, runs with the requested animation.
    @MainActor
    static func animate(_ token: Animation,
                        reduceMotion: Bool? = nil,
                        _ body: () -> Void) {
        let shouldReduce = reduceMotion ?? UIAccessibility.isReduceMotionEnabled
        if shouldReduce {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx, body)
        } else {
            withAnimation(token, body)
        }
    }
}
