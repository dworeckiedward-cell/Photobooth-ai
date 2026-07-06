import Foundation

/// RA2 — restore "active event" context after a crash or force-quit.
///
/// Event UX problem: operator enters event A, records a few takes, app
/// crashes (or iOS force-quits it due to backgrounding + memory pressure).
/// Re-launching drops them at the Event Picker — they have to drill back
/// through events list → event A → recording. 10-20s of fumbling with
/// guests in the queue.
///
/// Solution: persist the *currently active* event id in UserDefaults
/// whenever the operator enters its hub. Clear it when they back out
/// intentionally. At app launch, after auth + events list load, if the
/// stashed id matches a known event, push straight to that hub.
///
/// We **deliberately don't restore further than the hub** — recording
/// must be an intentional tap. Restoring straight into Recording would
/// hot-mic the operator (and possibly the guest who walked away mid-crash).
enum CrashRestoreManager {
    private static let key = "boothify.lastActiveEvent"

    /// Stash the id. Call on enter EventHub / Booth360EventHub / recording.
    /// Safe to call repeatedly with the same id (no-op write).
    static func setActiveEvent(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: key)
    }

    /// Clear on intentional exit (operator tapped back from EventHub to
    /// EventPicker). NOT called on crash — that's the whole point.
    static func clearActiveEvent() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Read the last stashed id at launch. Returns nil if never set or
    /// previously cleared.
    static func lastActiveEventId() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return UUID(uuidString: raw)
    }

    // MARK: - Phase 8: in-flight render (blueprint §8 crash recovery)

    private static let renderKey = "boothify.activeRenderJob"

    /// Stash while an export runs; cleared on completion/failure/cancel.
    static func setActiveRender(_ jobId: UUID) {
        UserDefaults.standard.set(jobId.uuidString, forKey: renderKey)
    }

    static func clearActiveRender() {
        UserDefaults.standard.removeObject(forKey: renderKey)
    }

    /// Non-nil at launch ⇒ the app died mid-export. The in-memory job is gone,
    /// but raw takes persist under Documents/events/<id>/ — the operator is
    /// told, loudly, instead of a clip vanishing silently.
    static func interruptedRenderId() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: renderKey) else { return nil }
        return UUID(uuidString: raw)
    }
}
