import SwiftUI

/// RA6 — Boothify type scale.
///
/// Backs every text token with Apple's semantic font (`.largeTitle`,
/// `.body`, `.caption`, etc.) so Dynamic Type scales them out of the
/// box. Avoid `.system(size: N)` outside this file — operators with
/// Accessibility large-text on otherwise see the rest of the UI scale
/// while one hardcoded label stays pinned.
///
/// Pick a token by intent:
/// - `display`        — top-of-screen titles (event name, mode picker)
/// - `displayMedium`  — section headers (Settings, sheets)
/// - `title`          — cards, dialogs, prominent labels
/// - `body`           — most paragraph copy
/// - `bodyEmphasis`   — body with extra weight (form labels, primary CTA)
/// - `caption`        — secondary labels, timestamps, status pills
/// - `mono`           — numerals + codes (timers, %, short codes) —
///                      automatically `.monospacedDigit()` so values
///                      don't jitter as they tick.
///
/// Special-purpose holdouts (single-callsite, intentional):
/// - countdown numerals (220pt rounded) live inline because they're a
///   one-off display element.
/// - Apple-Pay-style stylized hero brand wordmarks live inline because
///   they're brand, not type-system.
enum BoothifyType {
    static let display       = Font.system(.largeTitle, design: .default).weight(.bold)
    static let displayMedium = Font.system(.title,      design: .default).weight(.bold)
    static let title         = Font.system(.title2,     design: .default).weight(.semibold)
    static let body          = Font.system(.body,       design: .default)
    static let bodyEmphasis  = Font.system(.body,       design: .default).weight(.semibold)
    static let caption       = Font.system(.caption,    design: .default)
    static let mono          = Font.system(.body,       design: .default).weight(.semibold).monospacedDigit()
}
