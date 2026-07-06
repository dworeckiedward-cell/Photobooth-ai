import SwiftUI

// All Settings detail screens live here. Each is a standalone `View` plugged into
// `RootView.destination(for:)`. They share the same shape: read from
// `app.settings(for: eventId)`, mutate a nested struct via inline `Binding`, persist
// back via `app.updateSettings(_:for:)`. Persistence is implicit on every keystroke
// because the Binding setter writes UserDefaults synchronously.

// MARK: - Binding helpers

private extension AppState {
    func binding<Value>(
        eventId: UUID,
        keyPath: WritableKeyPath<EventSettings, Value>
    ) -> Binding<Value> {
        Binding(
            get: { self.settings(for: eventId)[keyPath: keyPath] },
            set: { newValue in
                var all = self.settings(for: eventId)
                all[keyPath: keyPath] = newValue
                self.updateSettings(all, for: eventId)
            }
        )
    }
}

// MARK: - Capture Settings

struct CameraSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    var body: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                SettingsCard(title: "Camera") {
                    SettingsPicker("Preferred camera", selection: app.binding(eventId: eventId, keyPath: \.camera.preferredCamera)) {
                        ForEach(CameraSide.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    SettingsDivider()
                    SettingsToggle("Mirror selfie", isOn: app.binding(eventId: eventId, keyPath: \.camera.mirrorSelfie))
                    SettingsDivider()
                    SettingsToggle("Video stabilization", isOn: Binding(
                        get: { app.settings(for: eventId).camera.stabilizationEnabled ?? true },
                        set: { newValue in
                            var all = app.settings(for: eventId)
                            all.camera.stabilizationEnabled = newValue
                            app.updateSettings(all, for: eventId)
                        }
                    ))
                    Text("Smooths 360 / slow-mo footage on a moving rig (cinematic stabilization). Adds a little capture latency — turn off for a static camera.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }

                SettingsCard(title: "Framing") {
                    SettingsSlider(
                        "Zoom",
                        value: app.binding(eventId: eventId, keyPath: \.camera.zoom),
                        in: 1.0...3.0,
                        step: 0.1,
                        valueLabel: String(format: "%.1f×", app.settings(for: eventId).camera.zoom)
                    )
                    SettingsDivider()
                    SettingsPicker("Rotation", selection: app.binding(eventId: eventId, keyPath: \.camera.rotation)) {
                        ForEach(CameraRotation.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }

                SettingsCard(title: "Flash") {
                    SettingsPicker("Behavior", selection: app.binding(eventId: eventId, keyPath: \.camera.flash)) {
                        ForEach(FlashBehavior.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                }

                SettingsCard(title: "Advanced") {
                    SettingsToggle("Roaming photographer", isOn: app.binding(eventId: eventId, keyPath: \.camera.roamingPhotographerMode))
                    SettingsDivider()
                    SettingsToggle("Record in PAL 25 FPS", isOn: app.binding(eventId: eventId, keyPath: \.camera.pal25FpsRecording))
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.md)
        }
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .navigationTitle("Camera Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI Portraits

struct AI360SettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    private var timelineSubtitle: String {
        let s = app.settings(for: eventId).ai360
        let segs = s.effectiveSegments
        let totalRaw = segs.reduce(0) { $0 + $1.duration }
        let totalRendered = segs.reduce(0) { $0 + $1.renderedDuration }
        return "\(segs.count) segment\(segs.count == 1 ? "" : "s") · raw \(format(totalRaw))s → \(format(totalRendered))s"
    }

    private func format(_ value: Double) -> String { String(format: "%.1f", value) }

    var body: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                SettingsCard(title: "Motion") {
                    SettingsPicker("Template", selection: Binding<MotionTemplate>(
                        get: { MotionTemplate(rawValue: app.settings(for: eventId).ai360.motionTemplate ?? "") ?? .heroSlow },
                        set: { newValue in
                            var all = app.settings(for: eventId)
                            all.ai360.motionTemplate = newValue.rawValue
                            app.updateSettings(all, for: eventId)
                        }
                    )) {
                        ForEach(MotionTemplate.allCases) { Text($0.label).tag($0) }
                    }
                    SettingsPicker("Ramp feel", selection: Binding<RampCurve>(
                        get: { RampCurve(rawValue: app.settings(for: eventId).ai360.rampCurve ?? "") ?? .gentle },
                        set: { newValue in
                            var all = app.settings(for: eventId)
                            all.ai360.rampCurve = newValue.rawValue
                            app.updateSettings(all, for: eventId)
                        }
                    )) {
                        ForEach(RampCurve.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    Text("One clear hero beat with eased ramps. Slow-motion always uses real captured frames — on cameras without high-speed capture the hero is gently limited, never faked.")
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }

                SettingsCard(title: "Recording") {
                    SettingsStepper(
                        "Countdown",
                        value: app.binding(eventId: eventId, keyPath: \.ai360.countdownSeconds),
                        range: 0...10,
                        valueLabel: "\(app.settings(for: eventId).ai360.countdownSeconds)s"
                    )
                    SettingsDivider()
                    SettingsSlider(
                        "Recording duration",
                        value: app.binding(eventId: eventId, keyPath: \.ai360.recordingDurationSeconds),
                        in: 2.0...20.0,
                        step: 0.5,
                        valueLabel: String(format: "%.1fs", app.settings(for: eventId).ai360.recordingDurationSeconds)
                    )
                    SettingsDivider()
                    SettingsToggle("Save original video", isOn: app.binding(eventId: eventId, keyPath: \.ai360.saveOriginalVideo))
                    SettingsDivider()
                    SettingsToggle("Blink flash while recording", isOn: app.binding(eventId: eventId, keyPath: \.ai360.blinkFlashWhileRecording))
                }

                SettingsCard(title: "Quality") {
                    SettingsPicker("Output size", selection: app.binding(eventId: eventId, keyPath: \.ai360.videoQuality)) {
                        ForEach(VideoQuality.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    SettingsDivider()
                    SettingsSlider(
                        "Bitrate",
                        value: app.binding(eventId: eventId, keyPath: \.ai360.bitrateMbps),
                        in: 4.0...30.0,
                        step: 1.0,
                        valueLabel: String(format: "%.0f Mbps", app.settings(for: eventId).ai360.bitrateMbps)
                    )
                }

                SettingsCard(title: "Auto-start") {
                    SettingsToggle("Start when device is moved", isOn: app.binding(eventId: eventId, keyPath: \.ai360.autoStartOnMovement))
                    if app.settings(for: eventId).ai360.autoStartOnMovement {
                        SettingsDivider()
                        SettingsSlider(
                            "Sensitivity",
                            value: app.binding(eventId: eventId, keyPath: \.ai360.movementSensitivity),
                            in: 0...1,
                            valueLabel: "\(Int(app.settings(for: eventId).ai360.movementSensitivity * 100))%"
                        )
                    }
                }

                SettingsCard(title: "Timeline") {
                    NavigationLink {
                        CaptureTimelineEditor(eventId: eventId)
                    } label: {
                        HStack(spacing: BoothifySpacing.sm) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .foregroundStyle(BoothifyTheme.amber)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Capture timeline")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white)
                                Text(timelineSubtitle)
                                    .font(.caption)
                                    .foregroundStyle(BoothifyTheme.textTertiary)
                            }
                            Spacer()
                        }
                    }
                    Text("Build the slow-mo / speed-ramp / reverse montage. Default preset loads if you don't customise.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }

                SettingsCard(title: "Clip (fallback)") {
                    SettingsPicker("Direction", selection: app.binding(eventId: eventId, keyPath: \.ai360.clipDirection)) {
                        ForEach(ClipDirection.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    SettingsDivider()
                    SettingsSlider(
                        "Speed",
                        value: app.binding(eventId: eventId, keyPath: \.ai360.clipSpeed),
                        in: 0.25...2.0,
                        step: 0.05,
                        valueLabel: String(format: "%.2f×", app.settings(for: eventId).ai360.clipSpeed)
                    )
                }

                SettingsCard(title: "Pre-record text") {
                    TextField("\"Get ready!\"", text: app.binding(eventId: eventId, keyPath: \.ai360.displayTextBeforeRecording))
                        .foregroundStyle(.white)
                }

                SettingsCard(title: "Soundtrack & overlays") {
                    ComingSoonRow(label: "Soundtrack", value: app.settings(for: eventId).ai360.soundtrackName ?? "None")
                    SettingsDivider()
                    ComingSoonRow(label: "Image overlay", value: app.settings(for: eventId).ai360.imageOverlayName ?? "None")
                    SettingsDivider()
                    ComingSoonRow(label: "Animated overlay", value: app.settings(for: eventId).ai360.animatedOverlayName ?? "None")
                    SettingsDivider()
                    ComingSoonRow(label: "Before-recording overlay", value: app.settings(for: eventId).ai360.beforeRecordingOverlayName ?? "None")
                    SettingsDivider()
                    ComingSoonRow(label: "After-recording overlay", value: app.settings(for: eventId).ai360.afterRecordingOverlayName ?? "None")
                }

                SettingsCard(title: "Preview") {
                    Text("Preview / test recording will appear here once the AI 360 capture pipeline ships.")
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.md)
        }
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .navigationTitle("AI 360 Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Effects

struct SharingSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID


    var body: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                SettingsCard(title: "Channels") {
                    ForEach(Array(SharingChannel.allCases.enumerated()), id: \.offset) { idx, ch in
                        let isOn = Binding(
                            get: { app.settings(for: eventId).sharing.enabledChannels.contains(ch) },
                            set: { newValue in
                                var all = app.settings(for: eventId)
                                if newValue { all.sharing.enabledChannels.insert(ch) }
                                else { all.sharing.enabledChannels.remove(ch) }
                                app.updateSettings(all, for: eventId)
                            }
                        )
                        if idx > 0 { SettingsDivider() }
                        Toggle(isOn: isOn) {
                            HStack(spacing: BoothifySpacing.sm + 2) {
                                Image(systemName: ch.symbol)
                                    .frame(width: 22)
                                    .foregroundStyle(BoothifyTheme.violet)
                                Text(ch.label)
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                            }
                        }
                        .tint(BoothifyTheme.violet)
                    }
                }

                SettingsCard(title: "Limits") {
                    SettingsToggle("Require guest opt-in", isOn: app.binding(eventId: eventId, keyPath: \.sharing.requireGuestOptIn))
                    SettingsDivider()
                    SettingsStepper(
                        "Max sends per guest",
                        value: app.binding(eventId: eventId, keyPath: \.sharing.maxSendsPerGuest),
                        range: 1...20,
                        valueLabel: "\(app.settings(for: eventId).sharing.maxSendsPerGuest)"
                    )
                }

                SettingsCard(title: "Public URL pattern") {
                    TextField("/p/{photoId}", text: app.binding(eventId: eventId, keyPath: \.sharing.publicResultUrlPattern))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .foregroundStyle(.white)
                        .font(.system(.body, design: .monospaced))
                    Text("Tokens: {photoId}, {eventSlug}. Path is appended to PUBLIC_RESULT_BASE_URL.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.md)
        }
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
    }

}

// MARK: - Email / SMS

struct EmailSMSSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var connectPresented: Bool = false

    private var twilioConfigured: Bool {
        TwilioClient.shared.currentCredentials()?.isConfigured == true
    }

    private var twilioStatusLabel: String {
        guard let creds = TwilioClient.shared.currentCredentials(), creds.isConfigured else {
            return "Not connected"
        }
        return "Connected · From \(creds.fromNumber)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                SettingsCard(title: "Sender") {
                    SettingsTextField("Sender name", text: app.binding(eventId: eventId, keyPath: \.emailSMS.senderName))
                    SettingsDivider()
                    SettingsToggle("Include Boothify branding in email", isOn: app.binding(eventId: eventId, keyPath: \.emailSMS.includeBrandingInEmail))
                }

                SettingsCard(title: "Email") {
                    SettingsTextField("Subject", text: app.binding(eventId: eventId, keyPath: \.emailSMS.emailSubject))
                    SettingsDivider()
                    TextField("Body template", text: app.binding(eventId: eventId, keyPath: \.emailSMS.emailBodyTemplate), axis: .vertical)
                        .lineLimit(4...10)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                }

                SettingsCard(title: "SMS provider") {
                    HStack(spacing: BoothifySpacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous)
                                .fill(twilioConfigured ? BoothifyTheme.emerald.opacity(0.15) : BoothifyTheme.amber.opacity(0.15))
                                .frame(width: 40, height: 40)
                            Image(systemName: twilioConfigured ? "checkmark.seal.fill" : "antenna.radiowaves.left.and.right.slash")
                                .foregroundStyle(twilioConfigured ? BoothifyTheme.emerald : BoothifyTheme.amber)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Twilio SMS")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                            Text(twilioStatusLabel)
                                .font(.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                        Button(twilioConfigured ? "Manage" : "Connect") {
                            connectPresented = true
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .controlSize(.small)
                    }
                    if twilioConfigured {
                        SettingsDivider()
                        SettingsTextField(
                            "Override From (optional, E.164)",
                            text: app.binding(eventId: eventId, keyPath: \.emailSMS.smsFromOverride),
                            keyboardType: .phonePad
                        )
                    }
                    Text(twilioConfigured
                         ? "Leave the override blank to use the global Twilio number across all events."
                         : "Connect your Twilio account to send SMS to guests. iOS talks to Twilio directly — your credentials never leave the device.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }

                SettingsCard(title: "SMS template") {
                    TextField("SMS template", text: app.binding(eventId: eventId, keyPath: \.emailSMS.smsBodyTemplate), axis: .vertical)
                        .lineLimit(2...6)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("Tokens: {{link}} for the public photo URL, {{style}} for the style name, {{eventName}}.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.md)
        }
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .navigationTitle("Email / SMS")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $connectPresented) {
            TwilioOnboardingSheet()
                .presentationDetents([.large])
        }
    }
}

// MARK: - Lock PIN

struct LockPinSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var pinInput: String = ""
    @State private var confirmInput: String = ""
    @State private var inlineError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: BoothifySpacing.md) {
                SettingsCard {
                    SettingsToggle("Enable PIN lock", isOn: app.binding(eventId: eventId, keyPath: \.lockPin.enabled))
                    Text("Guests can use the kiosk freely; operator actions (settings, sign out, gallery edit) require the PIN.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }

                if app.settings(for: eventId).lockPin.enabled {
                    SettingsCard(title: "Auto-lock idle timeout") {
                        SettingsPicker("Timeout", selection: app.binding(eventId: eventId, keyPath: \.lockPin.idleTimeoutMinutes)) {
                            Text("Never").tag(0)
                            Text("1 min").tag(1)
                            Text("5 min").tag(5)
                            Text("15 min").tag(15)
                            Text("30 min").tag(30)
                        }
                    }

                    SettingsCard(title: "Set / change PIN") {
                        SecureField("New PIN (4–6 digits)", text: $pinInput)
                            .keyboardType(.numberPad)
                            .foregroundStyle(.white)
                        SettingsDivider()
                        SecureField("Confirm PIN", text: $confirmInput)
                            .keyboardType(.numberPad)
                            .foregroundStyle(.white)

                        if let inlineError {
                            HStack(spacing: BoothifySpacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                Text(inlineError)
                                    .font(.footnote)
                            }
                            .foregroundStyle(BoothifyTheme.error)
                            .padding(.top, BoothifySpacing.xs)
                        }

                        Button("Save PIN") { savePin() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(pinInput.count < 4)
                            .padding(.top, BoothifySpacing.sm)
                    }
                }
            }
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.md)
        }
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .navigationTitle("Lock PIN")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func savePin() {
        guard pinInput.count >= 4, pinInput.count <= 6 else {
            inlineError = "PIN must be 4 to 6 digits."
            return
        }
        guard pinInput == confirmInput else {
            inlineError = "PINs don't match."
            return
        }
        guard pinInput.allSatisfy(\.isNumber) else {
            inlineError = "Digits only."
            return
        }
        var all = app.settings(for: eventId)
        all.lockPin.pin = pinInput
        app.updateSettings(all, for: eventId)
        pinInput = ""
        confirmInput = ""
        inlineError = nil
        Haptics.notify(.success)
    }
}

// MARK: - Gallery / Slideshow

private struct SettingsCard<Content: View>: View {
    var title: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .padding(.bottom, BoothifySpacing.xs)
            }
            VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
                content
            }
            .padding(BoothifySpacing.md)
            .boothifySurface(radius: BoothifyRadius.card)
        }
    }
}

// MARK: - Row helpers

private struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(BoothifyTheme.surfaceLine)
            .frame(height: 1)
    }
}

private struct LabeledRow: View {
    let title: String
    let value: String
    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }
    var body: some View {
        HStack {
            Text(title).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(BoothifyTheme.textTertiary)
        }
        .font(.subheadline)
    }
}

private struct ComingSoonRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.white)
            Spacer()
            Text(value).foregroundStyle(BoothifyTheme.textTertiary)
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(BoothifyTheme.textMuted)
        }
        .font(.subheadline)
        .opacity(0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value), coming soon")
    }
}

// MARK: - Styled row wrappers

private struct SettingsToggle: View {
    let title: String
    let isOn: Binding<Bool>
    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }
    var body: some View {
        Toggle(isOn: isOn) {
            Text(title).font(.subheadline).foregroundStyle(.white)
        }
        .tint(BoothifyTheme.violet)
    }
}

private struct SettingsTextField: View {
    let placeholder: String
    let text: Binding<String>
    var keyboardType: UIKeyboardType = .default
    init(_ placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) {
        self.placeholder = placeholder
        self.text = text
        self.keyboardType = keyboardType
    }
    var body: some View {
        TextField(placeholder, text: text)
            .foregroundStyle(.white)
            .font(.subheadline)
            .keyboardType(keyboardType)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
    }
}

private struct SettingsPicker<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let selection: Binding<SelectionValue>
    @ViewBuilder let content: Content

    init(_ title: String, selection: Binding<SelectionValue>, @ViewBuilder content: () -> Content) {
        self.title = title
        self.selection = selection
        self.content = content()
    }

    var body: some View {
        Picker(title, selection: selection) {
            content
        }
        .tint(BoothifyTheme.textSecondary)
    }
}

private struct SettingsStepper<V: Strideable>: View where V.Stride: BinaryInteger {
    let title: String
    let value: Binding<V>
    let range: ClosedRange<V>
    var step: V.Stride = 1
    let valueLabel: String

    init(_ title: String, value: Binding<V>, range: ClosedRange<V>, step: V.Stride = 1, valueLabel: String) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.valueLabel = valueLabel
    }

    var body: some View {
        Stepper(value: value, in: range, step: step) {
            LabeledRow(title, value: valueLabel)
        }
    }
}

private struct SettingsSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    var step: Double = 0
    let valueLabel: String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double = 0, valueLabel: String) {
        self.title = title
        self.value = value
        self.range = range
        self.step = step
        self.valueLabel = valueLabel
    }

    var body: some View {
        VStack(spacing: BoothifySpacing.xs) {
            LabeledRow(title, value: valueLabel)
            if step > 0 {
                Slider(value: value, in: range, step: step)
                    .tint(BoothifyTheme.violet)
            } else {
                Slider(value: value, in: range)
                    .tint(BoothifyTheme.violet)
            }
        }
    }
}
