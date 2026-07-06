import Foundation

/// Phase 7 — delivery policy (blueprint §7.8, §3 "Delivery reality").
///
/// Clips are heavy (8–15 MB): SMS is a LINK channel, never an attachment;
/// oversized Best-Quality masters auto-fall back to Fast Share for the share
/// copy. Pure functions — Gate A tests assert the policy directly.
enum DeliveryPolicy {
    /// Above this, a clip is too heavy to hand around casually — re-export the
    /// SHARE copy at Fast Share. (Master stays whatever the operator chose.)
    static let maxShareBytes: Int = 16_000_000

    /// Should the share copy drop to Fast Share?
    static func shouldFallbackToFastShare(bytes: Int, preset: RenderSpec.Preset) -> Bool {
        preset == .bestQuality && bytes > maxShareBytes
    }

    /// Final SMS body: the operator's template with placeholders filled —
    /// and a DEFENSIVE guarantee that the link is present. If an operator
    /// edits the template and drops `{{link}}`, the guest still gets a
    /// working link appended (a pretty SMS without a link delivers nothing).
    static func smsBody(template: String, link: URL, eventName: String) -> String {
        var body = template
            .replacingOccurrences(of: "{{link}}", with: link.absoluteString)
            .replacingOccurrences(of: "{{eventName}}", with: eventName)
        if !body.contains(link.absoluteString) {
            body = body.trimmingCharacters(in: .whitespacesAndNewlines) + " " + link.absoluteString
        }
        return body
    }
}
