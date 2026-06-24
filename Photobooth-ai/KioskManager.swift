import UIKit

/// Kiosk / unattended-event helpers.
///
/// Two independent concerns:
///  1. **Keep awake** — stop the device auto-locking during a live session or TV
///     slideshow. This is the #1 unattended-event pain point and needs no MDM.
///  2. **Single App Mode (ASAM)** — lock the device to this app so a guest can't
///     swipe home or switch apps. ASAM only engages on devices that are supervised
///     and have allow-listed the app via MDM; on unmanaged devices it is a no-op,
///     and operators use Guided Access (triple-click) instead. We call it anyway so
///     managed fleets get true lockdown for free, and report the result.
@MainActor
enum KioskManager {

    /// Prevent / allow the idle timer (screen auto-lock). Reference-counted so
    /// nested callers (camera + slideshow) don't clobber each other.
    private static var keepAwakeCount = 0

    static func beginKeepAwake() {
        keepAwakeCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func endKeepAwake() {
        keepAwakeCount = max(0, keepAwakeCount - 1)
        if keepAwakeCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    /// True when the OS is currently in a Guided Access / Single App session.
    static var isGuidedAccessActive: Bool {
        UIAccessibility.isGuidedAccessEnabled
    }

    /// Request Autonomous Single App Mode. Succeeds only on supervised + allow-listed
    /// devices; the completion reports whether the OS granted it so callers can fall
    /// back to prompting the operator to use Guided Access.
    static func requestSingleAppMode(_ enabled: Bool, completion: ((Bool) -> Void)? = nil) {
        UIAccessibility.requestGuidedAccessSession(enabled: enabled) { success in
            completion?(success)
        }
    }
}
