import SwiftUI

// All Settings detail screens live here. Each is a standalone `View` plugged into
// `RootView.destination(for:)`. They share the same shape: read from
// `app.settings(for: eventId)`, mutate a nested struct via inline `Binding`, persist
// back via `app.updateSettings(_:for:)`. Persistence is implicit on every keystroke
// because the Binding setter writes UserDefaults synchronously.

// MARK: - Binding helpers
//
// One small generic helper avoids 8x copy-pasting the same get/set scaffolding.

private extension AppState {
    /// Build a binding to a nested struct inside the per-event settings. Reads
    /// from the observable cache; writes back through `updateSettings(_:for:)`.
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

struct CaptureSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Capture mode", selection: app.binding(eventId: eventId, keyPath: \.capture.mode)) {
                    ForEach(CaptureMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Countdown") {
                Stepper(value: app.binding(eventId: eventId, keyPath: \.capture.countdownFirstPhoto), in: 0...10) {
                    LabeledRow("First photo", value: "\(app.settings(for: eventId).capture.countdownFirstPhoto)s")
                }
                Stepper(value: app.binding(eventId: eventId, keyPath: \.capture.countdownOtherPhotos), in: 0...10) {
                    LabeledRow("Other photos", value: "\(app.settings(for: eventId).capture.countdownOtherPhotos)s")
                }
            }
            Section("Multi-photo") {
                Stepper(value: app.binding(eventId: eventId, keyPath: \.capture.numberOfPhotos), in: 1...12) {
                    LabeledRow("Number of photos", value: "\(app.settings(for: eventId).capture.numberOfPhotos)")
                }
                HStack {
                    Text("Delay between frames")
                    Spacer()
                    Text("\(app.settings(for: eventId).capture.delayBetweenFrames, specifier: "%.1f")s")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.binding(eventId: eventId, keyPath: \.capture.delayBetweenFrames), in: 0.0...3.0, step: 0.1)
                Stepper(value: app.binding(eventId: eventId, keyPath: \.capture.displayEachPhotoDuration), in: 1...10) {
                    LabeledRow("Each photo display", value: "\(app.settings(for: eventId).capture.displayEachPhotoDuration)s")
                }
            }
            Section("Output") {
                Picker("Aspect ratio", selection: app.binding(eventId: eventId, keyPath: \.capture.outputSize)) {
                    ForEach(OutputSize.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("JPEG quality")
                    Spacer()
                    Text("\(Int(app.settings(for: eventId).capture.quality * 100))%")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.binding(eventId: eventId, keyPath: \.capture.quality), in: 0.4...1.0, step: 0.05)
            }
            Section("Animated") {
                Toggle("Also generate GIF", isOn: app.binding(eventId: eventId, keyPath: \.capture.alsoGenerateGif))
                Toggle("Reverse GIF", isOn: app.binding(eventId: eventId, keyPath: \.capture.reverseGif))
                    .disabled(!app.settings(for: eventId).capture.alsoGenerateGif)
            }
            Section("Modes") {
                Toggle("Roaming photographer", isOn: app.binding(eventId: eventId, keyPath: \.capture.roamingPhotographerMode))
            }
        }
        .styledFormBackground()
        .navigationTitle("Capture Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Camera Settings

struct CameraSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    var body: some View {
        Form {
            Section("Camera") {
                Picker("Preferred camera", selection: app.binding(eventId: eventId, keyPath: \.camera.preferredCamera)) {
                    ForEach(CameraSide.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Mirror selfie", isOn: app.binding(eventId: eventId, keyPath: \.camera.mirrorSelfie))
            }
            Section("Framing") {
                HStack {
                    Text("Zoom")
                    Spacer()
                    Text("\(app.settings(for: eventId).camera.zoom, specifier: "%.1f")×")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.binding(eventId: eventId, keyPath: \.camera.zoom), in: 1.0...3.0, step: 0.1)
                Picker("Rotation", selection: app.binding(eventId: eventId, keyPath: \.camera.rotation)) {
                    ForEach(CameraRotation.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Flash") {
                Picker("Behavior", selection: app.binding(eventId: eventId, keyPath: \.camera.flash)) {
                    ForEach(FlashBehavior.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Advanced") {
                Toggle("Roaming photographer", isOn: app.binding(eventId: eventId, keyPath: \.camera.roamingPhotographerMode))
                Toggle("Record in PAL 25 FPS", isOn: app.binding(eventId: eventId, keyPath: \.camera.pal25FpsRecording))
            }
        }
        .styledFormBackground()
        .navigationTitle("Camera Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI Portraits

struct AIPortraitsSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    var body: some View {
        Form {
            Section {
                Toggle("Face fidelity prompt", isOn: app.binding(eventId: eventId, keyPath: \.aiPortraits.faceFidelityEnabled))
            } footer: {
                Text("Adds a master prompt to every style that keeps the guest's face recognizable.")
            }

            Section("Generation") {
                Stepper(value: app.binding(eventId: eventId, keyPath: \.aiPortraits.generationTimeoutSeconds), in: 15...180, step: 15) {
                    LabeledRow("Timeout", value: "\(app.settings(for: eventId).aiPortraits.generationTimeoutSeconds)s")
                }
            }

            Section("Prompt overlay") {
                Toggle("Add custom prompt fragment", isOn: app.binding(eventId: eventId, keyPath: \.aiPortraits.customPromptOverlayEnabled))
                if app.settings(for: eventId).aiPortraits.customPromptOverlayEnabled {
                    TextField("e.g. brand-themed colour palette", text: app.binding(eventId: eventId, keyPath: \.aiPortraits.customPromptOverlay), axis: .vertical)
                        .lineLimit(2...4)
                }
            }

            Section("Enabled styles") {
                ForEach(PhotoStyle.allCases) { style in
                    let isOn = Binding(
                        get: { app.settings(for: eventId).aiPortraits.enabledStyles.contains(style) },
                        set: { newValue in
                            var all = app.settings(for: eventId)
                            if newValue { all.aiPortraits.enabledStyles.insert(style) }
                            else { all.aiPortraits.enabledStyles.remove(style) }
                            app.updateSettings(all, for: eventId)
                        }
                    )
                    Toggle(isOn: isOn) {
                        HStack(spacing: 12) {
                            Image(style.previewAsset)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.label)
                                    .font(.body)
                                Text(style.descriptionText)
                                    .font(.caption2)
                                    .foregroundStyle(BoothifyTheme.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .styledFormBackground()
        .navigationTitle("AI Portraits")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - AI 360

struct AI360SettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    var body: some View {
        Form {
            Section("Recording") {
                Stepper(value: app.binding(eventId: eventId, keyPath: \.ai360.countdownSeconds), in: 0...10) {
                    LabeledRow("Countdown", value: "\(app.settings(for: eventId).ai360.countdownSeconds)s")
                }
                HStack {
                    Text("Recording duration")
                    Spacer()
                    Text("\(app.settings(for: eventId).ai360.recordingDurationSeconds, specifier: "%.1f")s")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.binding(eventId: eventId, keyPath: \.ai360.recordingDurationSeconds), in: 2.0...20.0, step: 0.5)
                Toggle("Save original video", isOn: app.binding(eventId: eventId, keyPath: \.ai360.saveOriginalVideo))
                Toggle("Blink flash while recording", isOn: app.binding(eventId: eventId, keyPath: \.ai360.blinkFlashWhileRecording))
            }

            Section("Quality") {
                Picker("Output size", selection: app.binding(eventId: eventId, keyPath: \.ai360.videoQuality)) {
                    ForEach(VideoQuality.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Bitrate")
                    Spacer()
                    Text("\(app.settings(for: eventId).ai360.bitrateMbps, specifier: "%.0f") Mbps")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.binding(eventId: eventId, keyPath: \.ai360.bitrateMbps), in: 4.0...30.0, step: 1.0)
            }

            Section("Auto-start") {
                Toggle("Start when device is moved", isOn: app.binding(eventId: eventId, keyPath: \.ai360.autoStartOnMovement))
                if app.settings(for: eventId).ai360.autoStartOnMovement {
                    HStack {
                        Text("Sensitivity")
                        Spacer()
                        Text("\(Int(app.settings(for: eventId).ai360.movementSensitivity * 100))%")
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    Slider(value: app.binding(eventId: eventId, keyPath: \.ai360.movementSensitivity), in: 0...1)
                }
            }

            Section("Clip") {
                Picker("Direction", selection: app.binding(eventId: eventId, keyPath: \.ai360.clipDirection)) {
                    ForEach(ClipDirection.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                HStack {
                    Text("Speed")
                    Spacer()
                    Text("\(app.settings(for: eventId).ai360.clipSpeed, specifier: "%.2f")×")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.binding(eventId: eventId, keyPath: \.ai360.clipSpeed), in: 0.25...2.0, step: 0.05)
            }

            Section("Pre-record text") {
                TextField("\"Get ready!\"", text: app.binding(eventId: eventId, keyPath: \.ai360.displayTextBeforeRecording))
            }

            Section("Soundtrack & overlays (coming soon)") {
                ComingSoonRow(label: "Soundtrack", value: app.settings(for: eventId).ai360.soundtrackName ?? "None")
                ComingSoonRow(label: "Image overlay", value: app.settings(for: eventId).ai360.imageOverlayName ?? "None")
                ComingSoonRow(label: "Animated overlay", value: app.settings(for: eventId).ai360.animatedOverlayName ?? "None")
                ComingSoonRow(label: "Before-recording overlay", value: app.settings(for: eventId).ai360.beforeRecordingOverlayName ?? "None")
                ComingSoonRow(label: "After-recording overlay", value: app.settings(for: eventId).ai360.afterRecordingOverlayName ?? "None")
            }

            Section {
                Text("Preview / test recording will appear here once the AI 360 capture pipeline ships.")
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textTertiary)
            } header: { Text("Preview") }
        }
        .styledFormBackground()
        .navigationTitle("AI 360 Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Effects

struct EffectsSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    private let filters = ["", "Vintage", "Noir", "Cinematic", "Warm", "Cool"]

    var body: some View {
        Form {
            Section("Beauty") {
                Toggle("Beautify", isOn: app.binding(eventId: eventId, keyPath: \.effects.beautifyEnabled))
                if app.settings(for: eventId).effects.beautifyEnabled {
                    HStack {
                        Text("Intensity")
                        Spacer()
                        Text("\(Int(app.settings(for: eventId).effects.beautifyIntensity * 100))%")
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    Slider(value: app.binding(eventId: eventId, keyPath: \.effects.beautifyIntensity), in: 0...1)
                }
            }
            Section("Filter") {
                Picker("Filter", selection: Binding(
                    get: { app.settings(for: eventId).effects.filterName ?? "" },
                    set: { newValue in
                        var all = app.settings(for: eventId)
                        all.effects.filterName = newValue.isEmpty ? nil : newValue
                        app.updateSettings(all, for: eventId)
                    }
                )) {
                    Text("None").tag("")
                    ForEach(filters.filter { !$0.isEmpty }, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Grain & vignette") {
                Toggle("Grain", isOn: app.binding(eventId: eventId, keyPath: \.effects.grainEnabled))
                Toggle("Vignette", isOn: app.binding(eventId: eventId, keyPath: \.effects.vignetteEnabled))
            }
        }
        .styledFormBackground()
        .navigationTitle("Effects")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Sharing

struct SharingSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var saveShareModeError: String? = nil
    @State private var savingShareMode: Bool = false

    private var currentShareMode: ShareMode {
        app.event(id: eventId)?.effectiveShareMode ?? .private
    }

    var body: some View {
        Form {
            // M3: per-event share mode toggle. Drives whether guests receive
            // unique links (private — default) or whether everyone tapping the
            // event QR sees the whole album (public).
            Section {
                Picker("Share mode", selection: Binding<ShareMode>(
                    get: { currentShareMode },
                    set: { newMode in
                        applyShareMode(newMode)
                    }
                )) {
                    ForEach(ShareMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                if savingShareMode {
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.7)
                        Text("Saving…")
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }
                if let saveShareModeError {
                    Text(saveShareModeError)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                }
            } header: {
                Text("Album privacy")
            } footer: {
                Text(currentShareMode == .private
                     ? "Each guest receives a link to only their own photo or 360 video."
                     : "All photos and 360 videos from this event are visible via a single album link.")
                    .font(.caption2)
            }

            Section("Channels") {
                ForEach(SharingChannel.allCases, id: \.self) { ch in
                    let isOn = Binding(
                        get: { app.settings(for: eventId).sharing.enabledChannels.contains(ch) },
                        set: { newValue in
                            var all = app.settings(for: eventId)
                            if newValue { all.sharing.enabledChannels.insert(ch) }
                            else { all.sharing.enabledChannels.remove(ch) }
                            app.updateSettings(all, for: eventId)
                        }
                    )
                    Toggle(isOn: isOn) {
                        HStack(spacing: 10) {
                            Image(systemName: ch.symbol)
                                .frame(width: 22)
                                .foregroundStyle(BoothifyTheme.violet)
                            Text(ch.label)
                        }
                    }
                }
            }
            Section("Limits") {
                Toggle("Require guest opt-in", isOn: app.binding(eventId: eventId, keyPath: \.sharing.requireGuestOptIn))
                Stepper(value: app.binding(eventId: eventId, keyPath: \.sharing.maxSendsPerGuest), in: 1...20) {
                    LabeledRow("Max sends per guest", value: "\(app.settings(for: eventId).sharing.maxSendsPerGuest)")
                }
            }
            Section {
                TextField("/p/{photoId}", text: app.binding(eventId: eventId, keyPath: \.sharing.publicResultUrlPattern))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("Public URL pattern")
            } footer: {
                Text("Tokens: {photoId}, {eventSlug}. Path is appended to PUBLIC_RESULT_BASE_URL.")
                    .font(.caption2)
            }
        }
        .styledFormBackground()
        .navigationTitle("Sharing")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Optimistically apply the new share mode locally, then PATCH the backend.
    /// On failure: keep the local value (so the user can keep configuring) but
    /// surface the error so they know server didn't accept it.
    private func applyShareMode(_ mode: ShareMode) {
        guard let event = app.event(id: eventId), event.effectiveShareMode != mode else { return }

        // Optimistic local update so the picker reflects the choice immediately.
        var optimistic = event
        optimistic.shareMode = mode
        if let idx = app.events.firstIndex(where: { $0.id == event.id }) {
            app.events[idx] = optimistic
        }

        // Backend round-trip — silently no-op in demo mode (no session).
        guard app.isAuthenticated else {
            saveShareModeError = nil
            return
        }
        savingShareMode = true
        saveShareModeError = nil
        Task {
            do {
                let updated = try await BoothifyAPI.shared.updateEventShareMode(slug: event.slug, shareMode: mode)
                if let idx = app.events.firstIndex(where: { $0.id == updated.id }) {
                    app.events[idx] = updated
                }
            } catch {
                // Backend likely hasn't shipped the share_mode column yet.
                // We don't roll back: the local pref is still a valid signal
                // until cloud catches up.
                saveShareModeError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            savingShareMode = false
        }
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
        Form {
            Section("Sender") {
                TextField("Sender name", text: app.binding(eventId: eventId, keyPath: \.emailSMS.senderName))
                Toggle("Include Boothify branding in email", isOn: app.binding(eventId: eventId, keyPath: \.emailSMS.includeBrandingInEmail))
            }
            Section("Email") {
                TextField("Subject", text: app.binding(eventId: eventId, keyPath: \.emailSMS.emailSubject))
                TextField("Body template", text: app.binding(eventId: eventId, keyPath: \.emailSMS.emailBodyTemplate), axis: .vertical)
                    .lineLimit(4...10)
                    .font(.system(.body, design: .monospaced))
            }

            // M5: per-operator Twilio config. Direct REST integration — no
            // backend brokering — so operator pays for their own SMS and
            // chooses their own number.
            Section {
                HStack {
                    Image(systemName: twilioConfigured ? "checkmark.seal.fill" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(twilioConfigured ? BoothifyTheme.emerald : BoothifyTheme.amber)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Twilio SMS")
                            .foregroundStyle(.white)
                        Text(twilioStatusLabel)
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    Spacer()
                    Button(twilioConfigured ? "Manage" : "Connect") {
                        connectPresented = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BoothifyTheme.violet)
                }
                if twilioConfigured {
                    TextField("Override From (optional, E.164)",
                              text: app.binding(eventId: eventId, keyPath: \.emailSMS.smsFromOverride))
                        .keyboardType(.phonePad)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } header: {
                Text("SMS provider")
            } footer: {
                Text(twilioConfigured
                     ? "Leave the override blank to use the global Twilio number across all events."
                     : "Connect your Twilio account to send SMS to guests. iOS talks to Twilio directly — your credentials never leave the device.")
                    .font(.caption2)
            }

            Section {
                TextField("SMS template", text: app.binding(eventId: eventId, keyPath: \.emailSMS.smsBodyTemplate), axis: .vertical)
                    .lineLimit(2...6)
                    .font(.system(.body, design: .monospaced))
            } header: {
                Text("SMS template")
            } footer: {
                Text("Tokens: {{link}} for the public photo URL, {{style}} for the style name, {{eventName}}.")
                    .font(.caption2)
            }
        }
        .styledFormBackground()
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
        Form {
            Section {
                Toggle("Enable PIN lock", isOn: app.binding(eventId: eventId, keyPath: \.lockPin.enabled))
            } footer: {
                Text("Guests can use the kiosk freely; operator actions (settings, sign out, gallery edit) require the PIN.")
                    .font(.caption2)
            }

            if app.settings(for: eventId).lockPin.enabled {
                Section("Auto-lock idle timeout") {
                    Picker("Timeout", selection: app.binding(eventId: eventId, keyPath: \.lockPin.idleTimeoutMinutes)) {
                        Text("Never").tag(0)
                        Text("1 min").tag(1)
                        Text("5 min").tag(5)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                    }
                }

                Section("Set / change PIN") {
                    SecureField("New PIN (4–6 digits)", text: $pinInput)
                        .keyboardType(.numberPad)
                    SecureField("Confirm PIN", text: $confirmInput)
                        .keyboardType(.numberPad)
                    if let inlineError {
                        Text(inlineError).font(.footnote).foregroundStyle(.red.opacity(0.85))
                    }
                    Button("Save PIN") { savePin() }
                        .disabled(pinInput.count < 4)
                }
            }
        }
        .styledFormBackground()
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

struct GallerySlideshowSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    var body: some View {
        Form {
            Section("Slideshow") {
                Stepper(value: app.binding(eventId: eventId, keyPath: \.gallerySlideshow.slideIntervalSeconds), in: 2...30) {
                    LabeledRow("Interval", value: "\(app.settings(for: eventId).gallerySlideshow.slideIntervalSeconds)s")
                }
                Picker("Transition", selection: app.binding(eventId: eventId, keyPath: \.gallerySlideshow.transitionStyle)) {
                    ForEach(SlideTransition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Toggle("Randomize order", isOn: app.binding(eventId: eventId, keyPath: \.gallerySlideshow.randomizeOrder))
                Toggle("Show style label", isOn: app.binding(eventId: eventId, keyPath: \.gallerySlideshow.showStyleLabel))
            }
        }
        .styledFormBackground()
        .navigationTitle("Gallery & Slideshow")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tiny row helpers

private struct LabeledRow: View {
    let title: String
    let value: String
    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }
    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(BoothifyTheme.textTertiary)
        }
    }
}

private struct ComingSoonRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(BoothifyTheme.textTertiary)
            Image(systemName: "lock.fill")
                .font(.caption2)
                .foregroundStyle(BoothifyTheme.textMuted)
        }
        .opacity(0.55)
    }
}

// MARK: - Form chrome

private extension View {
    /// Dark form background that hides the system white scroll content.
    func styledFormBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(BoothifyTheme.bg.ignoresSafeArea())
    }
}
