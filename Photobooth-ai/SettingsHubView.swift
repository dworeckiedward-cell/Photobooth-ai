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
        // Layout redesign: designed settings, not a generic iOS list. The
        // atmosphere breathes under floating glass sections; icons carry the
        // amber accent (the blue-drift era is over); rows stay light.
        ZStack {
            AtmosphericBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BoothifySpacing.lg) {
                    // Identity — light glass, amber aperture.
                    if let event {
                        HStack(spacing: BoothifySpacing.md) {
                            AppIconBadge(symbol: "camera.aperture", color: BoothifyTheme.violet, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name)
                                    .font(.headline)
                                    .foregroundStyle(.white)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(BoothifyTheme.emerald)
                                        .frame(width: 6, height: 6)
                                    Text("\(event.completedPhotos) of \(event.totalPhotos) photos")
                                        .font(.subheadline)
                                        .foregroundStyle(BoothifyTheme.textSecondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(BoothifySpacing.md)
                        .glassSurface(radius: BoothifyRadius.section)
                    }

                    // Quick Setup — the 2 most critical items for new operators.
                    SettingsSectionCard(title: "Quick Setup") {
                        SettingsRow(icon: "camera.rotate", title: "Camera Settings", subtitle: cameraSubtitle) {
                            app.push(.settingsCamera(eventId: eventId))
                        }
                        SettingsRow(icon: "lock.fill", title: "Lock PIN", subtitle: app.settings(for: eventId).lockPin.enabled ? "Enabled" : "Off") {
                            app.push(.settingsLockPin(eventId: eventId))
                        }
                    }

                    // Set Up — rows are filtered by the current event's BoothMode so
                    // each panel stays focused on what the operator configures here.
                    SettingsSectionCard(title: "Set Up") {
                        SettingsRow(icon: "video.fill", title: "360 Booth", subtitle: ai360Subtitle) {
                            app.push(.settingsAI360(eventId: eventId))
                        }
                        SettingsRow(icon: "camera.rotate", title: "Camera Settings", subtitle: cameraSubtitle) {
                            app.push(.settingsCamera(eventId: eventId))
                        }
                        SettingsRow(icon: "rosette", title: "Brand Overlay", subtitle: brandOverlaySubtitle) {
                            app.push(.settingsStickers(eventId: eventId))
                        }
                    }

                    SettingsSectionCard(title: "Sharing Add-ons") {
                        SettingsRow(icon: "envelope.fill", title: "Email / SMS", subtitle: "Templates & sender") {
                            app.push(.settingsEmailSMS(eventId: eventId))
                        }
                        SettingsRow(icon: "square.and.arrow.up", title: "Sharing channels", subtitle: "\(app.settings(for: eventId).sharing.enabledChannels.count) channels on") {
                            app.push(.settingsSharing(eventId: eventId))
                        }
                        SettingsRow(icon: "person.fill.questionmark", title: "On-screen Assistant", subtitle: virtualAttendantSubtitle) {
                            app.push(.settingsVirtualAttendant(eventId: eventId))
                        }
                        SettingsRow(icon: "doc.text", title: "Disclaimer", subtitle: disclaimerSubtitle) {
                            app.push(.settingsDisclaimer(eventId: eventId))
                        }
                        SettingsRow(icon: "checklist", title: "Survey", subtitle: surveySubtitle) {
                            app.push(.settingsSurvey(eventId: eventId))
                        }
                    }

                    // Gallery & Slideshow settings now live inside Album/Gallery
                    // toolbar — intentionally NOT shown as a primary row here.

                    SettingsSectionCard(title: "More") {
                        SettingsRow(icon: "antenna.radiowaves.left.and.right", title: "Delivery Status", subtitle: "Delivery channels") {
                            app.push(.settingsSharingStatus(eventId: eventId))
                        }
                        SettingsRow(icon: "lock.fill", title: "Lock PIN", subtitle: app.settings(for: eventId).lockPin.enabled ? "Enabled" : "Off") {
                            app.push(.settingsLockPin(eventId: eventId))
                        }
                        SettingsRow(icon: "person.circle", title: "Account", subtitle: "Event info, reset") {
                            app.push(.settingsAccount(eventId: eventId))
                        }
                        SettingsRow(icon: "info.circle", title: "About Boothify", subtitle: "Version & credits") {
                            app.push(.aboutBoothify)
                        }
                    }
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.top, BoothifySpacing.sm)
                .padding(.bottom, BoothifySpacing.xl)
                .frame(maxWidth: .infinity)
            }
        }
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

    private var ai360Subtitle: String {
        let s = app.settings(for: eventId).ai360
        return "\(Int(s.recordingDurationSeconds))s · \(s.videoQuality.label)"
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
        case .demo:      BoothifyTheme.violet
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
                        // AVAILABLE is the norm, not news — only demo/beta
                        // states earn a badge (anti-noise).
                        if let badge, badge != .available {
                            Text(badge.label)
                                .font(.caption2.weight(.bold))
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
            AtmosphericBackground()
            VStack(spacing: BoothifySpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                        .fill(BoothifyTheme.surface1)
                        .frame(width: 72, height: 72)
                        .overlay(
                            RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                        )
                    Image(systemName: "clock.badge.questionmark")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.violet)
                        .accessibilityHidden(true)
                }
                VStack(spacing: BoothifySpacing.xs) {
                    Text("Coming soon")
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                    Text(blurb)
                        .font(.subheadline)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, BoothifySpacing.xxl)
                }
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
            AtmosphericBackground()
            VStack(spacing: BoothifySpacing.lg) {
                // Logo with surface card
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous)
                        .fill(BoothifyTheme.surface1)
                        .frame(width: 100, height: 100)
                        .overlay(
                            RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous)
                                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
                    Image("BoothifyLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
                .padding(.top, BoothifySpacing.xl)

                VStack(spacing: BoothifySpacing.xs) {
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
                    .padding(.horizontal, BoothifySpacing.xxl)

                Spacer()
            }
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
