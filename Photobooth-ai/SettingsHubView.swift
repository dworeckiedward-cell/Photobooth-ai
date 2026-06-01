import SwiftUI

/// Top-level Settings hub for an event. Inspired by Lumabooth's operator panel.
/// Sections roughly: Set Up · Sharing Add-ons · More.
///
/// Some rows route to fully wired detail screens; others route to a shared
/// `ComingSoonView` so the surface area is complete even before features ship.
enum BoothMode: Hashable, Sendable {
    case photobooth
    case ai360
}

struct SettingsHubView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID
    var mode: BoothMode = .photobooth

    private var event: Event? { app.event(id: eventId) }

    var body: some View {
        List {
            // Identity block
            if let event {
                Section {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(BoothifyTheme.violet)
                                .frame(width: 52, height: 52)
                            Image(systemName: "camera.aperture")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.name)
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("\(event.completedPhotos) of \(event.totalPhotos) photos")
                                .font(.subheadline)
                                .foregroundStyle(BoothifyTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(BoothifyTheme.surface1)
                }
            }

            // Set Up — rows are filtered by the current event's BoothMode so each
            // panel stays focused on what the operator actually configures here.
            Section("Set Up") {
                if mode == .photobooth {
                    SettingsRow(icon: "slider.horizontal.3", title: "Capture Settings", subtitle: "Countdown, output, GIF", badge: .available) {
                        app.push(.settingsCapture(eventId: eventId))
                    }
                    SettingsRow(icon: "printer", title: "Print Setup", subtitle: printSubtitle, badge: .available) {
                        app.push(.settingsPrint(eventId: eventId))
                    }
                    SettingsRow(icon: "person.crop.rectangle.badge.xmark", title: "Background Removal", subtitle: backgroundRemovalSubtitle, badge: .available) {
                        app.push(.settingsBackgroundRemoval(eventId: eventId))
                    }
                    SettingsRow(icon: "camera.rotate", title: "Camera Settings", subtitle: cameraSubtitle, badge: .available) {
                        app.push(.settingsCamera(eventId: eventId))
                    }
                    SettingsRow(icon: "rosette", title: "Brand Overlay", subtitle: brandOverlaySubtitle, badge: .available) {
                        app.push(.settingsStickers(eventId: eventId))
                    }
                    SettingsRow(icon: "sparkles", title: "Effects", subtitle: effectsSubtitle, badge: .available) {
                        app.push(.settingsEffects(eventId: eventId))
                    }
                    SettingsRow(icon: "wand.and.stars", title: "AI Portraits", subtitle: "\(app.settings(for: eventId).aiPortraits.enabledStyles.count) styles enabled", badge: .beta) {
                        app.push(.settingsAIPortraits(eventId: eventId))
                    }
                } else {
                    // 360 mode — surface AI 360 settings + the universal pieces.
                    SettingsRow(icon: "video.fill", title: "AI 360 Booth", subtitle: ai360Subtitle, badge: .beta) {
                        app.push(.settingsAI360(eventId: eventId))
                    }
                    SettingsRow(icon: "rosette", title: "Brand Overlay", subtitle: brandOverlaySubtitle, badge: .available) {
                        app.push(.settingsStickers(eventId: eventId))
                    }
                    SettingsRow(icon: "sparkles", title: "Effects", subtitle: effectsSubtitle, badge: .available) {
                        app.push(.settingsEffects(eventId: eventId))
                    }
                }
            }
            .listRowBackground(BoothifyTheme.surface1)

            // Sharing Add-ons
            Section("Sharing Add-ons") {
                SettingsRow(icon: "envelope.fill", title: "Email / SMS", subtitle: "Templates & sender", badge: .available) {
                    app.push(.settingsEmailSMS(eventId: eventId))
                }
                SettingsRow(icon: "square.and.arrow.up", title: "Sharing channels", subtitle: "\(app.settings(for: eventId).sharing.enabledChannels.count) channels on", badge: .available) {
                    app.push(.settingsSharing(eventId: eventId))
                }
                SettingsRow(icon: "person.fill.questionmark", title: "On-screen Assistant", subtitle: virtualAttendantSubtitle, badge: .available) {
                    app.push(.settingsVirtualAttendant(eventId: eventId))
                }
                SettingsRow(icon: "doc.text", title: "Disclaimer", subtitle: disclaimerSubtitle, badge: .available) {
                    app.push(.settingsDisclaimer(eventId: eventId))
                }
                SettingsRow(icon: "checklist", title: "Survey", subtitle: surveySubtitle, badge: .available) {
                    app.push(.settingsSurvey(eventId: eventId))
                }
            }
            .listRowBackground(BoothifyTheme.surface1)

            // Gallery & Slideshow settings now live inside Album/Gallery toolbar —
            // intentionally NOT shown as a primary SettingsHub row.

            // More
            Section("More") {
                SettingsRow(icon: "antenna.radiowaves.left.and.right", title: "Delivery Status", subtitle: "Channels & test sends", badge: .available) {
                    app.push(.settingsSharingStatus(eventId: eventId))
                }
                SettingsRow(icon: "lock.fill", title: "Lock PIN", subtitle: app.settings(for: eventId).lockPin.enabled ? "Enabled" : "Off", badge: .available) {
                    app.push(.settingsLockPin(eventId: eventId))
                }
                SettingsRow(icon: "person.circle", title: "Account", subtitle: "Event info, reset", badge: .available) {
                    app.push(.settingsAccount(eventId: eventId))
                }
                SettingsRow(icon: "info.circle", title: "About Boothify", subtitle: "Version & credits") {
                    app.push(.aboutBoothify)
                }
            }
            .listRowBackground(BoothifyTheme.surface1)
        }
        .scrollContentBackground(.hidden)
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var cameraSubtitle: String {
        let s = app.settings(for: eventId).camera
        var parts: [String] = []
        parts.append(s.preferredCamera == .front ? "Front" : "Back")
        if s.mirrorSelfie { parts.append("Mirrored") }
        return parts.joined(separator: " · ")
    }

    private var effectsSubtitle: String {
        let s = app.settings(for: eventId).effects
        var bits: [String] = []
        if s.beautifyEnabled { bits.append("Beautify") }
        if let f = s.filterName { bits.append(f.capitalized) }
        if s.grainEnabled { bits.append("Grain") }
        if s.vignetteEnabled { bits.append("Vignette") }
        return bits.isEmpty ? "Off" : bits.joined(separator: " · ")
    }

    private var ai360Subtitle: String {
        let s = app.settings(for: eventId).ai360
        return "\(Int(s.recordingDurationSeconds))s · \(s.videoQuality.label)"
    }

    private var printSubtitle: String {
        let s = app.settings(for: eventId).print
        if !s.enabled { return "Off" }
        return "\(s.paperSize.label) · \(s.layout.label)"
    }

    private var backgroundRemovalSubtitle: String {
        let s = app.settings(for: eventId).backgroundRemoval
        return s.enabled ? s.mode.label : "Off"
    }

    private var brandOverlaySubtitle: String {
        let s = app.settings(for: eventId).brandOverlay
        if !s.enabled { return "Logo watermark off" }
        return "Logo overlay enabled"
    }

    private var virtualAttendantSubtitle: String {
        app.settings(for: eventId).virtualAttendant.enabled ? "On" : "Off"
    }

    private var disclaimerSubtitle: String {
        let s = app.settings(for: eventId).disclaimer
        if !s.enabled { return "Off" }
        return s.requireConsentBeforeCapture ? "Required before capture" : "Shown"
    }

    private var surveySubtitle: String {
        let s = app.settings(for: eventId).survey
        guard s.enabled else { return "Off" }
        return "\(s.answerType.label) · \(s.required ? "required" : "optional")"
    }
}

// MARK: - Reusable row

enum SettingsBadge: Hashable {
    /// Fully functional locally (e.g. settings persistence, UI flows).
    case available
    /// Mock/demo only — UI works, real integration not yet wired.
    case demo
    /// AI or partially wired feature behind a feature flag.
    case beta

    var label: String {
        switch self {
        case .available: "AVAILABLE"
        case .demo:      "DEMO"
        case .beta:      "BETA"
        }
    }

    var tint: Color {
        switch self {
        case .available: BoothifyTheme.emerald
        case .demo:      BoothifyTheme.amber
        case .beta:      BoothifyTheme.violet
        }
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    var disabled: Bool = false
    var badge: SettingsBadge? = nil
    let action: () -> Void

    var body: some View {
        Button(action: { Haptics.tap(); action() }) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(BoothifyTheme.surface2)
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(disabled ? BoothifyTheme.textMuted : BoothifyTheme.violet)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.body)
                            .foregroundStyle(disabled ? BoothifyTheme.textTertiary : .white)
                        if let badge {
                            Text(badge.label)
                                .font(.system(size: 9, weight: .bold))
                                .kerning(0.5)
                                .foregroundStyle(badge.tint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(badge.tint.opacity(0.15), in: Capsule())
                                .overlay(Capsule().stroke(badge.tint.opacity(0.45), lineWidth: 0.5))
                        }
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(disabled ? "\(title), coming soon" : title)
    }
}

// MARK: - Coming Soon

struct ComingSoonView: View {
    let title: String
    let blurb: String

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(BoothifyTheme.violet)
                    .accessibilityHidden(true)
                Text("Coming soon")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(blurb)
                    .font(.subheadline)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About

struct AboutBoothifyView: View {
    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()
            VStack(spacing: 24) {
                Image("BoothifyLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 100, height: 100)
                    .shadow(color: Color.black.opacity(0.35), radius: 22, y: 8)

                VStack(spacing: 6) {
                    Text("Boothify")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("Version \(version)")
                        .font(.subheadline)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }

                Text("AI photo booth platform for events.\nPowered by Servify Labs.")
                    .font(.callout)
                    .foregroundStyle(BoothifyTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Spacer()
            }
            .padding(.top, 32)
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        SettingsHubView(eventId: UUID())
    }
    .environment(AppState())
    .preferredColorScheme(.dark)
}
