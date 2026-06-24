import Foundation

/// One-tap event setup. Picking a template at event creation pre-configures the
/// settings that actually differ by event type — consent, lead capture, branding
/// and email tone — so an operator is ready in seconds instead of clicking through
/// every settings screen. (Styles stay all-on; guests enjoy the full set.)
enum EventTemplate: String, CaseIterable, Identifiable, Sendable {
    case wedding, birthday, corporate

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wedding:   "Wedding"
        case .birthday:  "Birthday"
        case .corporate: "Brand Event"
        }
    }

    /// Seeds the event-name field when the chip is tapped.
    var nameSeed: String {
        switch self {
        case .wedding:   "Wedding"
        case .birthday:  "Birthday Party"
        case .corporate: "Brand Event"
        }
    }

    /// Apply the template to a fresh event's settings. Only touches fields whose
    /// behavior is wired and meaningful — safe, no guessing.
    func apply(to base: EventSettings, eventName: String) -> EventSettings {
        var s = base
        let name = eventName.isEmpty ? label : eventName

        switch self {
        case .wedding:
            // Elegant + on-brand. Consent on (photos of guests), no survey friction.
            s.brandOverlay.enabled = true
            s.disclaimer.enabled = true
            s.disclaimer.requireConsentBeforeCapture = true
            s.disclaimer.disclaimerText =
                "By tapping continue you agree to your photo being processed by AI and shared via the channels chosen for this event. You can request deletion at any time."
            s.survey.enabled = false
            s.emailSMS.senderName = name
            s.emailSMS.emailSubject = "Your photo from \(name)"

        case .birthday:
            // Low-friction fun: no forms, no required consent gate. Branding off.
            s.brandOverlay.enabled = false
            s.disclaimer.enabled = false
            s.disclaimer.requireConsentBeforeCapture = false
            s.survey.enabled = false
            s.emailSMS.senderName = name
            s.emailSMS.emailSubject = "Your photo from \(name)"

        case .corporate:
            // Lead capture + brand. Survey on, consent on, logo on.
            s.brandOverlay.enabled = true
            s.disclaimer.enabled = true
            s.disclaimer.requireConsentBeforeCapture = true
            s.disclaimer.disclaimerText =
                "By continuing you consent to your photo being processed by AI, shared with you, and to \(name) contacting you about this event. You can request deletion at any time."
            s.survey.enabled = true
            s.survey.required = false
            s.survey.questionText = "Want us to follow up? Rate your experience."
            s.emailSMS.senderName = name
            s.emailSMS.emailSubject = "Your photo from \(name)"
            s.emailSMS.includeBrandingInEmail = true
        }
        return s
    }
}
