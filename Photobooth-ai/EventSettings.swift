import Foundation
import SwiftUI

/// Full event-level settings model. Codable so we can sync with backend JSONB
/// (Supabase `events.settings`) once that column is added. For MVP we keep it
/// in `AppState` and persist to `UserDefaults` per event id.
///
/// Shape follows the Lumabooth feature reference — sections roughly map to the
/// Settings Hub view sections (Set Up / Sharing Add-ons / More).
struct EventSettings: Codable, Hashable, Sendable {
    var capture: CaptureSettings
    var camera: CameraSettings
    var ai360: AI360Settings
    var sharing: SharingSettings
    var emailSMS: EmailSMSSettings
    var lockPin: LockPinSettings
    var gallerySlideshow: GallerySlideshowSettings

    var virtualAttendant: VirtualAttendantSettings
    var disclaimer: DisclaimerSettings
    var survey: SurveySettings
    var brandOverlay: BrandOverlaySettings

    static let `default` = EventSettings(
        capture: .default,
        camera: .default,
        ai360: .default,
        sharing: .default,
        emailSMS: .default,
        lockPin: .default,
        gallerySlideshow: .default,
        virtualAttendant: .default,
        disclaimer: .default,
        survey: .default,
        brandOverlay: .default
    )

    // Backward-compatible decoder: previously-persisted JSON didn't have the MVP
    // add-on fields. We decode each section defensively so old events keep loading
    // and just get default values for new sections.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Self.default
        self.capture            = (try? c.decode(CaptureSettings.self,           forKey: .capture))            ?? d.capture
        self.camera             = (try? c.decode(CameraSettings.self,            forKey: .camera))             ?? d.camera
        self.ai360              = (try? c.decode(AI360Settings.self,             forKey: .ai360))              ?? d.ai360
        self.sharing            = (try? c.decode(SharingSettings.self,           forKey: .sharing))            ?? d.sharing
        self.emailSMS           = (try? c.decode(EmailSMSSettings.self,          forKey: .emailSMS))           ?? d.emailSMS
        self.lockPin            = (try? c.decode(LockPinSettings.self,           forKey: .lockPin))            ?? d.lockPin
        self.gallerySlideshow   = (try? c.decode(GallerySlideshowSettings.self,  forKey: .gallerySlideshow))   ?? d.gallerySlideshow
        self.virtualAttendant   = (try? c.decode(VirtualAttendantSettings.self,  forKey: .virtualAttendant))   ?? d.virtualAttendant
        self.disclaimer         = (try? c.decode(DisclaimerSettings.self,        forKey: .disclaimer))         ?? d.disclaimer
        self.survey             = (try? c.decode(SurveySettings.self,            forKey: .survey))             ?? d.survey
        self.brandOverlay       = (try? c.decode(BrandOverlaySettings.self,      forKey: .brandOverlay))       ?? d.brandOverlay
    }

    // Memberwise init still needed because we added a custom decoder.
    init(
        capture: CaptureSettings,
        camera: CameraSettings,
        ai360: AI360Settings,
        sharing: SharingSettings,
        emailSMS: EmailSMSSettings,
        lockPin: LockPinSettings,
        gallerySlideshow: GallerySlideshowSettings,
        virtualAttendant: VirtualAttendantSettings,
        disclaimer: DisclaimerSettings,
        survey: SurveySettings,
        brandOverlay: BrandOverlaySettings
    ) {
        self.capture = capture
        self.camera = camera
        self.ai360 = ai360
        self.sharing = sharing
        self.emailSMS = emailSMS
        self.lockPin = lockPin
        self.gallerySlideshow = gallerySlideshow
        self.virtualAttendant = virtualAttendant
        self.disclaimer = disclaimer
        self.survey = survey
        self.brandOverlay = brandOverlay
    }
}

// MARK: - Capture

enum CaptureMode: String, Codable, CaseIterable, Hashable, Sendable {
    case singlePhoto, photoStrip, gif, boomerang, video

    var label: String {
        switch self {
        case .singlePhoto: "Single Photo"
        case .photoStrip:  "Photo Strip"
        case .gif:         "GIF"
        case .boomerang:   "Boomerang"
        case .video:       "Video"
        }
    }
}

enum OutputSize: String, Codable, CaseIterable, Hashable, Sendable {
    case square, portrait43, portrait916, landscape34, landscape169

    var label: String {
        switch self {
        case .square:        "Square (1:1)"
        case .portrait43:    "Portrait (4:5)"
        case .portrait916:   "Portrait (9:16)"
        case .landscape34:   "Landscape (4:3)"
        case .landscape169:  "Landscape (16:9)"
        }
    }
}

struct CaptureSettings: Codable, Hashable, Sendable {
    var mode: CaptureMode = .singlePhoto
    var countdownFirstPhoto: Int = 3
    var countdownOtherPhotos: Int = 2
    var displayEachPhotoDuration: Int = 3
    var numberOfPhotos: Int = 1
    var delayBetweenFrames: Double = 0.5
    var alsoGenerateGif: Bool = false
    var reverseGif: Bool = false
    var roamingPhotographerMode: Bool = false
    var outputSize: OutputSize = .square
    var quality: Double = 0.85

    static let `default` = CaptureSettings()
}

// MARK: - Camera

enum CameraSide: String, Codable, CaseIterable, Hashable, Sendable {
    case front, back

    var label: String {
        switch self { case .front: "Front"; case .back: "Back" }
    }
}

enum CameraRotation: Int, Codable, CaseIterable, Hashable, Sendable {
    case zero = 0, ninety = 90, oneEighty = 180, twoSeventy = 270

    var label: String { "\(rawValue)°" }
}

enum FlashBehavior: String, Codable, CaseIterable, Hashable, Sendable {
    case auto, on, off

    var label: String {
        switch self { case .auto: "Auto"; case .on: "On"; case .off: "Off" }
    }
}

struct CameraSettings: Codable, Hashable, Sendable {
    var preferredCamera: CameraSide = .front
    var zoom: Double = 1.0
    var rotation: CameraRotation = .zero
    var mirrorSelfie: Bool = true
    var roamingPhotographerMode: Bool = false
    var pal25FpsRecording: Bool = false
    var flash: FlashBehavior = .off
    /// Video stabilization for 360 / slow-mo recording (smooths platform vibration).
    /// Optional so older stored settings decode cleanly; nil is treated as ON.
    /// Adds a little capture latency, so operators on a static rig can turn it off.
    var stabilizationEnabled: Bool? = true

    static let `default` = CameraSettings()
}

// MARK: - AI Portraits

// MARK: - AI 360

enum VideoQuality: String, Codable, CaseIterable, Hashable, Sendable {
    case sd720p, hd1080p

    var label: String {
        switch self { case .sd720p: "720p"; case .hd1080p: "1080p" }
    }
}

enum ClipDirection: String, Codable, CaseIterable, Hashable, Sendable {
    case forwards, backwards, reverse

    var label: String {
        switch self {
        case .forwards:  "Forwards"
        case .backwards: "Backwards"
        case .reverse:   "Forwards + Reverse"
        }
    }
}

// MARK: - Sharing

enum SharingChannel: String, Codable, CaseIterable, Hashable, Sendable {
    case download, email, sms, whatsapp, qr, airdrop

    var label: String {
        switch self {
        case .download: "Download"
        case .email:    "Email"
        case .sms:      "SMS"
        case .whatsapp: "WhatsApp"
        case .qr:       "QR Code"
        case .airdrop:  "AirDrop"
        }
    }

    var symbol: String {
        switch self {
        case .download: "square.and.arrow.down"
        case .email:    "envelope.fill"
        case .sms:      "message.fill"
        case .whatsapp: "phone.bubble.fill"
        case .qr:       "qrcode"
        case .airdrop:  "airplayaudio"
        }
    }
}


struct AI360Settings: Codable, Hashable, Sendable {
    var countdownSeconds: Int = 3
    var recordingDurationSeconds: Double = 6.0
    var videoQuality: VideoQuality = .hd1080p
    var bitrateMbps: Double = 10.0
    var saveOriginalVideo: Bool = true
    var autoStartOnMovement: Bool = false
    var movementSensitivity: Double = 0.5    // placeholder — 0…1
    var displayTextBeforeRecording: String = "Get ready!"
    var blinkFlashWhileRecording: Bool = false
    var clipDirection: ClipDirection = .reverse
    var clipSpeed: Double = 1.0              // 0.25…2.0 typical
    var soundtrackName: String? = nil        // placeholder — pick from library later
    /// M4: relative path under `Documents/events/<eventId>/audio/` to the
    /// soundtrack picked via fileImporter. nil = no soundtrack. Stored as
    /// relative path (not absolute URL) so it survives app container changes.
    var soundtrackRelativePath: String? = nil
    var imageOverlayName: String? = nil      // placeholder
    var animatedOverlayName: String? = nil   // placeholder
    var beforeRecordingOverlayName: String? = nil
    var afterRecordingOverlayName: String? = nil

    /// M6: segmented timeline that drives the FFmpeg montage. When non-empty,
    /// the active template overrides the single `clipSpeed` / `clipDirection`
    /// values. We keep the singles for backward-compat — old persisted
    /// settings still decode and the renderer synthesises a one-segment
    /// template from them on the fly when `templates` is empty.
    var templates: [CaptureTemplate] = []
    var activeTemplateId: UUID? = nil

    /// Returns the segment list the renderer should actually use. Falls back
    /// to a one-segment template built from the legacy `clipSpeed` /
    /// `clipDirection` values when the operator hasn't touched the editor.
    var effectiveSegments: [CaptureSegment] {
        if let id = activeTemplateId,
           let template = templates.first(where: { $0.id == id }),
           !template.segments.isEmpty {
            return template.segments
        }
        // Backward-compat: one segment spanning the full recording at the
        // single legacy speed, with reverse-on-end iff direction == .reverse.
        return [
            CaptureSegment(
                duration: max(1, recordingDurationSeconds),
                speed: max(0.1, clipSpeed),
                reverse: clipDirection == .reverse || clipDirection == .backwards
            )
        ]
    }

    static let `default` = AI360Settings()
}

// MARK: - Capture timeline (M6)

/// One slice of the final montage. Render pipeline:
///   trim → setpts (speed) → optional reverse → concat
/// `duration` is the slice of RAW footage to consume (seconds), `speed` is
/// the playback multiplier (>1 faster, <1 slow-motion).
struct CaptureSegment: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var duration: Double
    var speed: Double
    var reverse: Bool = false

    /// Output duration after speed adjustment. Useful for the "total length"
    /// readout in the editor.
    var renderedDuration: Double {
        guard speed > 0 else { return duration }
        return duration / speed
    }
}

struct CaptureTemplate: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var segments: [CaptureSegment]

    /// Total raw footage required to satisfy this template.
    var rawDuration: Double { segments.reduce(0) { $0 + $1.duration } }
    /// Total length of the rendered output.
    var renderedDuration: Double { segments.reduce(0) { $0 + $1.renderedDuration } }

    /// Default sprint-1 preset — the "production" template Patryk validated.
    /// 9s of raw footage → ~12.6s rendered with a tasteful slow-mo mid and a
    /// punchy reverse outro.
    static let defaultProduction = CaptureTemplate(
        id: UUID(),
        name: "Production (default)",
        segments: [
            CaptureSegment(duration: 3.0, speed: 1.25, reverse: false),
            CaptureSegment(duration: 3.0, speed: 0.75, reverse: false),
            CaptureSegment(duration: 3.0, speed: 2.0,  reverse: true),
        ]
    )
}

// MARK: - Effects

struct SharingSettings: Codable, Hashable, Sendable {
    var enabledChannels: Set<SharingChannel>
    var requireGuestOptIn: Bool = false
    var publicResultUrlPattern: String = "/p/{photoId}"
    var maxSendsPerGuest: Int = 5
    /// Pre-populated test recipients used by Sharing Status. Operator can edit
    /// before running a "Send test" — replaces the previous hardcoded values.
    var testEmail: String = ""
    var testPhone: String = ""

    static let `default` = SharingSettings(
        enabledChannels: [.download, .email, .sms, .whatsapp, .qr]
    )
}

// MARK: - Email / SMS

struct EmailSMSSettings: Codable, Hashable, Sendable {
    var senderName: String = "Boothify"
    var emailSubject: String = "📸 Your photo from Boothify"
    var emailBodyTemplate: String =
        "Hi! Your AI photo is ready. Tap below to open it.\n\n{{link}}"
    var smsBodyTemplate: String = "Your Boothify photo is ready: {{link}}"
    var includeBrandingInEmail: Bool = true
    /// M5: optional per-event override for the SMS "From" number. When empty
    /// we use the operator's global TwilioCredentials.fromNumber. Useful when
    /// the operator runs multiple concurrent events from different numbers.
    var smsFromOverride: String = ""

    static let `default` = EmailSMSSettings()
}

// MARK: - Lock PIN

struct LockPinSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var pin: String = ""        // 4–6 digit numeric. Empty when disabled.
    var idleTimeoutMinutes: Int = 0   // 0 = never auto-lock

    static let `default` = LockPinSettings()
}

// MARK: - Gallery / Slideshow

struct GallerySlideshowSettings: Codable, Hashable, Sendable {
    var slideIntervalSeconds: Int = 5
    var transitionStyle: SlideTransition = .fade
    var showStyleLabel: Bool = false
    var randomizeOrder: Bool = false

    static let `default` = GallerySlideshowSettings()
}

enum SlideTransition: String, Codable, CaseIterable, Hashable, Sendable {
    case fade, slide, kenBurns

    var label: String {
        switch self {
        case .fade:     "Fade"
        case .slide:    "Slide"
        case .kenBurns: "Ken Burns"
        }
    }
}

// MARK: - Print Setup

enum PrintPaperSize: String, Codable, CaseIterable, Hashable, Sendable {
    case fourBySix, fiveBySeven, square, postcard

    var label: String {
        switch self {
        case .fourBySix:    "4×6 in"
        case .fiveBySeven:  "5×7 in"
        case .square:       "Square 4×4 in"
        case .postcard:     "Postcard A6"
        }
    }
}

enum PrintLayout: String, Codable, CaseIterable, Hashable, Sendable {
    case single, twoStrip, fourStrip, doubleSingle

    var label: String {
        switch self {
        case .single:        "Single photo"
        case .twoStrip:      "2-photo strip"
        case .fourStrip:     "Classic 4-photo strip"
        case .doubleSingle:  "Double single (2 copies)"
        }
    }
}

// MARK: - Stickers

enum StickerPack: String, Codable, CaseIterable, Hashable, Sendable {
    case wedding, birthday, corporate

    var label: String {
        switch self {
        case .wedding:    "Wedding"
        case .birthday:   "Birthday"
        case .corporate:  "Corporate"
        }
    }

    /// SF Symbol emoji set for the placeholder preview chips.
    var sampleSymbols: [String] {
        switch self {
        case .wedding:   ["heart.fill", "sparkles", "rings.fill", "gift.fill"]
        case .birthday:  ["birthday.cake.fill", "balloon.fill", "party.popper.fill", "music.note"]
        case .corporate: ["briefcase.fill", "checkmark.seal.fill", "trophy.fill", "chart.line.uptrend.xyaxis"]
        }
    }
}

// MARK: - Virtual Attendant

struct VirtualAttendantSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var greetingMessage: String = "Hi! Ready for your AI photo?"
    var voicePromptText: String = "Smile! We're taking the shot in a moment."
    var helpButtonEnabled: Bool = true
    var idleReminderEnabled: Bool = false
    var idleReminderSeconds: Int = 30

    static let `default` = VirtualAttendantSettings()
}

// MARK: - Disclaimer

struct DisclaimerSettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var disclaimerText: String =
        "By tapping continue you consent to your photo being processed by AI and shared via the channels selected for this event. You can request deletion at any time."
    var requireConsentBeforeCapture: Bool = false
    var consentCheckboxLabel: String = "I agree to the photo terms"

    static let `default` = DisclaimerSettings()
}

// MARK: - Survey

enum SurveyAnswerType: String, Codable, CaseIterable, Hashable, Sendable {
    case rating, text, yesNo

    var label: String {
        switch self {
        case .rating: "Rating (1–5)"
        case .text:   "Short text"
        case .yesNo:  "Yes / No"
        }
    }
}

struct SurveySettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var questionText: String = "How was your Boothify experience?"
    var answerType: SurveyAnswerType = .rating
    var required: Bool = false

    static let `default` = SurveySettings()
}

/// Lightweight in-memory store for collected survey answers. MVP: persisted to
/// UserDefaults under a per-event key, so operators can see local responses
/// without a backend table yet.
struct SurveyResponse: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var photoId: UUID?
    var answerType: SurveyAnswerType
    var rating: Int?
    var text: String?
    var yesNo: Bool?
    var submittedAt: Date = .now
}

/// Recorded disclaimer acceptance. MVP: local per-event UserDefaults log so
/// operators can prove consent during a demo. A backend table will replace this
/// once we add `consent_log` to Supabase.
struct ConsentRecord: Codable, Hashable, Sendable, Identifiable {
    var id: UUID = UUID()
    var acceptedAt: Date
    var deviceName: String
}

// MARK: - Brand Overlay
//
// Premium replacement for the old "Stickers" feature. Lets the operator drop a
// client logo, sponsor mark, event watermark, or text fallback onto every result.
// MVP: a single overlay layer (logo or text fallback), 5 anchor positions,
// size/opacity/padding controls, applied at render-time on iOS (no server-side
// composition yet).

enum BrandOverlayPosition: String, Codable, CaseIterable, Hashable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight, center

    var label: String {
        switch self {
        case .topLeft:     "Top left"
        case .topRight:    "Top right"
        case .bottomLeft:  "Bottom left"
        case .bottomRight: "Bottom right"
        case .center:      "Center"
        }
    }

    var alignment: Alignment {
        switch self {
        case .topLeft:     .topLeading
        case .topRight:    .topTrailing
        case .bottomLeft:  .bottomLeading
        case .bottomRight: .bottomTrailing
        case .center:      .center
        }
    }
}

enum BrandLogoSource: String, Codable, CaseIterable, Hashable, Sendable {
    case boothifySample, uploaded, textFallback

    var label: String {
        switch self {
        case .boothifySample: "Boothify sample logo"
        case .uploaded:       "Uploaded logo"
        case .textFallback:   "Text watermark"
        }
    }
}

struct BrandOverlaySettings: Codable, Hashable, Sendable {
    var enabled: Bool = false
    var applyToResults: Bool = true
    var logoSource: BrandLogoSource = .boothifySample
    /// Asset catalog name for uploaded/built-in image source. Defaults to the Boothify mark.
    var logoAssetName: String = "BoothifyLogo"
    /// M7: relative path under `Documents/events/<eventId>/` to an uploaded
    /// custom PNG. Used when `logoSource == .uploaded`. nil = no upload yet.
    var customLogoRelativePath: String? = nil
    /// Text used when `logoSource == .textFallback`.
    var overlayText: String = "ACME EVENT"
    var position: BrandOverlayPosition = .bottomRight
    /// Size as a fraction of the photo's shorter edge (0.05–0.40).
    var size: Double = 0.18
    /// 0 fully transparent → 1 fully opaque.
    var opacity: Double = 0.85
    /// Padding from the edge as a fraction of the photo's shorter edge (0.00–0.10).
    var padding: Double = 0.04
    var showOnOriginalCaptures: Bool = false
    var showOnAIResults: Bool = true

    static let `default` = BrandOverlaySettings()

    /// True when the overlay should render on top of an AI result. Convenience.
    var rendersOnResults: Bool { enabled && applyToResults && showOnAIResults }
}
