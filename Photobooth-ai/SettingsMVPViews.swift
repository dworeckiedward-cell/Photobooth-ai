import SwiftUI
import AVFoundation
import UIKit
import PhotosUI

// MVP add-on settings — hardened demo-ready pass. Each section saves persistently
// via `app.updateSettings(_:for:)` and shows realistic placeholders so the app feels
// like a finished operator tool during client demos.

// MARK: - Binding helper

private extension AppState {
    func mvpBinding<Value>(
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

private extension View {
    func mvpFormBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(AtmosphericBackground())
            .tint(BoothifyTheme.violet)
    }
}

// MARK: - Brand Overlay

struct BrandOverlaySettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var uploadError: String? = nil
    @State private var uploadSuccess: Bool = false

    private var s: BrandOverlaySettings { app.settings(for: eventId).brandOverlay }

    var body: some View {
        Form {
            Section {
                Toggle("Enable Brand Overlay", isOn: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.enabled))
            } footer: {
                Text("Add your client logo or event watermark to every shared result.")
                    .font(.caption2)
            }

            Section("Where it appears") {
                Toggle("Apply to 360 results", isOn: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.applyToResults))
                Toggle("Show on 360 videos", isOn: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.showOnAIResults))
                Toggle("Show on original captures", isOn: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.showOnOriginalCaptures))
            }
            .disabled(!s.enabled)

            Section("Logo source") {
                Picker("Source", selection: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.logoSource)) {
                    ForEach(BrandLogoSource.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()

                if s.logoSource == .boothifySample {
                    Button {
                        Haptics.tap()
                        var all = app.settings(for: eventId)
                        all.brandOverlay.logoAssetName = "BoothifyLogo"
                        app.updateSettings(all, for: eventId)
                    } label: {
                        Label("Use Boothify sample logo", systemImage: "checkmark.seal.fill")
                    }
                } else if s.logoSource == .uploaded {
                    // M7: real picker. Saves to Documents/events/<id>/logo.png
                    // and updates BrandOverlaySettings.customLogoRelativePath.
                    PhotosPicker(
                        selection: $pickerItem,
                        matching: .images,
                        preferredItemEncoding: .compatible
                    ) {
                        Label(
                            s.customLogoRelativePath == nil ? "Upload logo (PNG)" : "Replace logo",
                            systemImage: "square.and.arrow.up.fill"
                        )
                    }
                    if let uploadError {
                        Text(uploadError)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                    }
                    if uploadSuccess {
                        Label("Logo saved", systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.emerald)
                    }
                    if let path = s.customLogoRelativePath {
                        Text("Stored: \(path)")
                            .font(.caption2)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Button(role: .destructive) {
                            removeUploadedLogo()
                        } label: {
                            Label("Remove uploaded logo", systemImage: "trash")
                        }
                    }
                    Text("PNG with alpha recommended. Logo is rendered by the native video pipeline and composited on top of every 360 result.")
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                } else if s.logoSource == .textFallback {
                    TextField("Watermark text", text: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.overlayText))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
            }
            .disabled(!s.enabled)

            Section("Position") {
                Picker("Position", selection: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.position)) {
                    ForEach(BrandOverlayPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            .disabled(!s.enabled)

            Section("Size & opacity") {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(Int(s.size * 100))%")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.size), in: 0.05...0.40)
                HStack {
                    Text("Opacity")
                    Spacer()
                    Text("\(Int(s.opacity * 100))%")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.opacity), in: 0.10...1.0)
                HStack {
                    Text("Padding")
                    Spacer()
                    Text("\(Int(s.padding * 100))%")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Slider(value: app.mvpBinding(eventId: eventId, keyPath: \.brandOverlay.padding), in: 0.0...0.10)
            }
            .disabled(!s.enabled)

            Section("Live preview") {
                BrandOverlayPreviewCard(settings: s, eventId: eventId)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            }
        }
        .mvpFormBackground()
        .navigationTitle("Brand Overlay")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await handlePickedLogo(item) }
        }
    }

    private func handlePickedLogo(_ item: PhotosPickerItem) async {
        uploadError = nil
        uploadSuccess = false
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw NSError(domain: "Boothify", code: -30,
                              userInfo: [NSLocalizedDescriptionKey: "Couldn't read picked image."])
            }

            // Validate we got a decodable image. PNG preferred — keeps alpha.
            // If user picked a JPEG, accept it but warn (no transparency).
            guard let img = UIImage(data: data) else {
                throw NSError(domain: "Boothify", code: -31,
                              userInfo: [NSLocalizedDescriptionKey: "Picked file isn't an image we can read."])
            }
            // Re-encode as PNG so we always end up with consistent format on
            // disk. PhotosPicker doesn't guarantee PNG even when filtering.
            guard let pngData = img.pngData() else {
                throw NSError(domain: "Boothify", code: -32,
                              userInfo: [NSLocalizedDescriptionKey: "Couldn't encode logo as PNG."])
            }

            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let folder = docs
                .appendingPathComponent("events", isDirectory: true)
                .appendingPathComponent(eventId.uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let dest = folder.appendingPathComponent("logo.png")
            try pngData.write(to: dest, options: .atomic)

            var all = app.settings(for: eventId)
            all.brandOverlay.customLogoRelativePath = "logo.png"
            app.updateSettings(all, for: eventId)

            uploadSuccess = true
            Haptics.notify(.success)
            // Auto-dismiss success label after a beat.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2.5))
                uploadSuccess = false
            }
        } catch {
            uploadError = error.localizedDescription
            Haptics.notify(.error)
        }
        pickerItem = nil
    }

    private func removeUploadedLogo() {
        var all = app.settings(for: eventId)
        if let relative = all.brandOverlay.customLogoRelativePath {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let url = docs
                .appendingPathComponent("events", isDirectory: true)
                .appendingPathComponent(eventId.uuidString, isDirectory: true)
                .appendingPathComponent(relative)
            try? FileManager.default.removeItem(at: url)
        }
        all.brandOverlay.customLogoRelativePath = nil
        app.updateSettings(all, for: eventId)
        Haptics.notify(.success)
    }
}

/// Reusable composition: sample background + brand overlay rendered on top.
/// Used by Settings preview AND ResultView.
struct BrandOverlayLayer: View {
    let settings: BrandOverlaySettings
    /// M7: optional event scope so the layer can resolve `.uploaded` PNGs
    /// from `Documents/events/<eventId>/`. Omit to keep the previous bundled-
    /// asset behavior (used in static previews and the photo flow which
    /// passes the event id when wired).
    var eventId: UUID? = nil

    var body: some View {
        GeometryReader { proxy in
            let shorterEdge = min(proxy.size.width, proxy.size.height)
            let logoSide = shorterEdge * CGFloat(settings.size)
            let pad = shorterEdge * CGFloat(settings.padding)

            Group {
                switch settings.logoSource {
                case .boothifySample:
                    Image(settings.logoAssetName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: logoSide, height: logoSide)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                case .uploaded:
                    // Resolve uploaded PNG from disk if we have an event scope
                    // AND the relative path is set; otherwise fall through to
                    // the bundled asset so nothing blanks out the overlay.
                    if let eventId,
                       let relative = settings.customLogoRelativePath,
                       let image = Self.loadUploadedLogo(eventId: eventId, relative: relative) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: logoSide, height: logoSide)
                            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    } else {
                        Image(settings.logoAssetName)
                            .resizable()
                            .scaledToFit()
                            .frame(width: logoSide, height: logoSide)
                            .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                    }
                case .textFallback:
                    Text(settings.overlayText)
                        .font(.system(size: max(11, logoSide * 0.30), weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .kerning(1.2)
                        .padding(.horizontal, max(8, logoSide * 0.18))
                        .padding(.vertical, max(4, logoSide * 0.08))
                        .background(.black.opacity(0.42), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
                }
            }
            .opacity(settings.opacity)
            .padding(pad)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: settings.position.alignment)
        }
        .allowsHitTesting(false)
    }

    /// File lookup helper — kept static so it's testable + cheap. Returns nil
    /// if file missing / not decodable so the view can fall through to the
    /// bundled placeholder.
    static func loadUploadedLogo(eventId: UUID, relative: String) -> UIImage? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = docs
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
            .appendingPathComponent(relative)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Returns the on-disk URL for an event's uploaded logo (if any). The
    /// native video pipeline composites it per-frame during render.
    static func uploadedLogoURL(eventId: UUID, settings: BrandOverlaySettings) -> URL? {
        guard settings.logoSource == .uploaded,
              let relative = settings.customLogoRelativePath else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return docs
            .appendingPathComponent("events", isDirectory: true)
            .appendingPathComponent(eventId.uuidString, isDirectory: true)
            .appendingPathComponent(relative)
    }
}

private struct BrandOverlayPreviewCard: View {
    let settings: BrandOverlaySettings
    var eventId: UUID? = nil

    var body: some View {
        ZStack {
            Image("Style_superbohater")
                .resizable()
                .scaledToFill()

            if settings.enabled {
                BrandOverlayLayer(settings: settings, eventId: eventId)
            }
        }
        .clipped()
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 6) {
                Image(systemName: "rosette")
                    .font(.caption2)
                Text(settings.enabled ? "Brand overlay live" : "Overlay disabled")
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(8)
        }
    }
}

// MARK: - Virtual Attendant

struct VirtualAttendantSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID
    @State private var helpPresented = false

    private var s: VirtualAttendantSettings { app.settings(for: eventId).virtualAttendant }

    var body: some View {
        Form {
            Section {
                Toggle("Enable On-screen Assistant", isOn: app.mvpBinding(eventId: eventId, keyPath: \.virtualAttendant.enabled))
            } footer: {
                Text("Greeting + voice prompt on the capture screen. Voice playback uses on-device TTS — no audio leaves the phone.")
                    .font(.caption2)
            }

            Section("Messages") {
                TextField("Greeting message", text: app.mvpBinding(eventId: eventId, keyPath: \.virtualAttendant.greetingMessage), axis: .vertical)
                    .lineLimit(2...4)
                TextField("Voice prompt text", text: app.mvpBinding(eventId: eventId, keyPath: \.virtualAttendant.voicePromptText), axis: .vertical)
                    .lineLimit(2...4)
                Button {
                    AttendantSpeech.shared.play(s.voicePromptText)
                } label: {
                    Label("Play voice prompt", systemImage: "speaker.wave.2.fill")
                }
                .disabled(!s.enabled || s.voicePromptText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(!s.enabled)

            Section("Help & idle") {
                Toggle("Show help button on kiosk", isOn: app.mvpBinding(eventId: eventId, keyPath: \.virtualAttendant.helpButtonEnabled))
                Toggle("Idle reminder", isOn: app.mvpBinding(eventId: eventId, keyPath: \.virtualAttendant.idleReminderEnabled))
                if s.idleReminderEnabled {
                    Stepper(value: app.mvpBinding(eventId: eventId, keyPath: \.virtualAttendant.idleReminderSeconds), in: 5...300, step: 5) {
                        HStack {
                            Text("Reminder after")
                            Spacer()
                            Text("\(s.idleReminderSeconds)s").foregroundStyle(BoothifyTheme.textTertiary)
                        }
                    }
                }
                Button {
                    Haptics.tap()
                    helpPresented = true
                } label: {
                    Label("Preview help screen", systemImage: "questionmark.circle")
                }
            }
            .disabled(!s.enabled)

            Section("Preview") {
                VirtualAttendantPreview(greeting: s.greetingMessage, prompt: s.voicePromptText)
                    .listRowInsets(EdgeInsets())
            }
        }
        .mvpFormBackground()
        .navigationTitle("On-screen Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $helpPresented) {
            VirtualAttendantHelpSheet(settings: s)
                .presentationDetents([.large])
        }
    }
}

/// Reusable on-screen attendant prompt — drop into the capture flow when enabled.
struct VirtualAttendantPreview: View {
    let greeting: String
    let prompt: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(BoothifyTheme.violet.opacity(0.16))
                    .frame(width: 44, height: 44)
                Image(systemName: "person.wave.2.fill")
                    .foregroundStyle(BoothifyTheme.violet)
                    .font(.title3.weight(.semibold))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(prompt)
                    .font(.footnote)
                    .foregroundStyle(BoothifyTheme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassSurface(radius: 16)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .padding(12)
    }
}

struct VirtualAttendantHelpSheet: View {
    let settings: VirtualAttendantSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AtmosphericBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(BoothifyTheme.violet)
                        Text("Need a hand?")
                            .font(.largeTitle.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 24)

                    helpRow(
                        symbol: "1.circle.fill",
                        title: "Step into the frame",
                        body: "Stand 3–6 feet from the camera so your face fits comfortably."
                    )
                    helpRow(
                        symbol: "2.circle.fill",
                        title: "Tap the shutter",
                        body: "A 3-second countdown will start. Hold your pose."
                    )
                    helpRow(
                        symbol: "3.circle.fill",
                        title: "Pick a style",
                        body: "Choose any of the cinematic motion templates — the rest is automatic."
                    )
                    helpRow(
                        symbol: "4.circle.fill",
                        title: "Share your 360 video",
                        body: "Scan the QR code, or send to email/SMS — whatever the operator enabled."
                    )

                    if !settings.voicePromptText.trimmingCharacters(in: .whitespaces).isEmpty {
                        Divider().background(BoothifyTheme.surfaceLine).padding(.top, 6)
                        Button {
                            AttendantSpeech.shared.play(settings.voicePromptText)
                        } label: {
                            Label("Hear the voice prompt", systemImage: "speaker.wave.2.fill")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }

                    Spacer(minLength: 12)

                    Button("Got it") {
                        Haptics.tap()
                        dismiss()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private func helpRow(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(BoothifyTheme.violet)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(.white)
                Text(body).font(.subheadline).foregroundStyle(BoothifyTheme.textSecondary)
            }
        }
    }
}

/// On-device TTS singleton. Auto-stops in-flight utterances when a new one starts.
@MainActor
final class AttendantSpeech {
    static let shared = AttendantSpeech()
    private let synth = AVSpeechSynthesizer()

    private init() {}

    func play(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        let utt = AVSpeechUtterance(string: trimmed)
        utt.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utt.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        synth.speak(utt)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }
}

// MARK: - Disclaimer

struct DisclaimerSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID
    @State private var confirmReset = false

    private var s: DisclaimerSettings { app.settings(for: eventId).disclaimer }
    private var consents: [ConsentRecord] { app.consentLog(for: eventId) }

    var body: some View {
        Form {
            Section {
                Toggle("Show disclaimer", isOn: app.mvpBinding(eventId: eventId, keyPath: \.disclaimer.enabled))
                Toggle("Require consent before capture", isOn: app.mvpBinding(eventId: eventId, keyPath: \.disclaimer.requireConsentBeforeCapture))
                    .disabled(!s.enabled)
            } footer: {
                Text("A consent gate appears before the camera when both toggles are on. Each acceptance is logged locally for this event.")
                    .font(.caption2)
            }

            Section("Text") {
                TextField("Disclaimer body", text: app.mvpBinding(eventId: eventId, keyPath: \.disclaimer.disclaimerText), axis: .vertical)
                    .lineLimit(4...12)
                TextField("Consent checkbox label", text: app.mvpBinding(eventId: eventId, keyPath: \.disclaimer.consentCheckboxLabel))
            }
            .disabled(!s.enabled)

            Section {
                if let latest = consents.last {
                    LabeledRowInline(
                        title: "Last consent",
                        value: latest.acceptedAt.formatted(date: .abbreviated, time: .shortened)
                    )
                    LabeledRowInline(title: "Device", value: latest.deviceName)
                    LabeledRowInline(title: "Total recorded", value: "\(consents.count)")
                } else {
                    Text("No consent recorded yet.")
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Button(role: .destructive) {
                    Haptics.tap()
                    confirmReset = true
                } label: {
                    Label("Reset consent for this event", systemImage: "arrow.counterclockwise")
                }
                .disabled(consents.isEmpty)
            } header: {
                Text("Consent log")
            }
        }
        .mvpFormBackground()
        .navigationTitle("Disclaimer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset consent log?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                app.resetConsent(for: eventId)
                Haptics.notify(.success)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All locally-recorded acceptances for this event will be removed. Guests will see the consent screen again.")
        }
    }
}

/// Consent screen shown before camera when disclaimer requires it.
struct DisclaimerConsentSheet: View {
    let settings: DisclaimerSettings
    let onAccept: () -> Void
    let onDecline: () -> Void
    @State private var checked: Bool = false

    var body: some View {
        ZStack {
            AtmosphericBackground()
            VStack(alignment: .leading, spacing: 16) {
                Text("Before we start")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .padding(.top, 32)
                ScrollView {
                    Text(settings.disclaimerText)
                        .font(.body)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }
                .frame(maxHeight: 320)

                Toggle(isOn: $checked) {
                    Text(settings.consentCheckboxLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .tint(BoothifyTheme.violet)

                Spacer(minLength: 4)

                Button {
                    Haptics.notify(.success)
                    onAccept()
                } label: {
                    Text("Continue")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!checked)
                .opacity(checked ? 1 : 0.55)

                Button("Cancel") {
                    Haptics.tap()
                    onDecline()
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Survey

struct SurveySettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var csvShareURL: URL?
    @State private var showCSVShare = false
    @State private var csvError: String?

    private var s: SurveySettings { app.settings(for: eventId).survey }
    private var responses: [SurveyResponse] { app.surveyResponses(for: eventId) }

    private func exportCSV() {
        let eventName = app.events.first(where: { $0.id == eventId })?.name ?? "event"
        let csv = CSVExporter.surveyCSV(responses, question: s.questionText)
        if let url = CSVExporter.writeTemp(csv, name: "boothify-\(eventName)-responses") {
            csvShareURL = url
            showCSVShare = true
        } else {
            // Don't fail silently — the operator tapped Export and expects feedback.
            Haptics.notify(.error)
            csvError = "Couldn't write the CSV. Check that the device has free storage and try again."
        }
    }

    var body: some View {
        Form {
            Section {
                Toggle("Show post-photo survey", isOn: app.mvpBinding(eventId: eventId, keyPath: \.survey.enabled))
                Toggle("Required", isOn: app.mvpBinding(eventId: eventId, keyPath: \.survey.required))
                    .disabled(!s.enabled)
            } footer: {
                Text("One question shown after the result screen. Responses save locally per event; backend table comes later.")
                    .font(.caption2)
            }

            Section("Question") {
                TextField("Question", text: app.mvpBinding(eventId: eventId, keyPath: \.survey.questionText), axis: .vertical)
                    .lineLimit(2...4)
                Picker("Answer type", selection: app.mvpBinding(eventId: eventId, keyPath: \.survey.answerType)) {
                    ForEach(SurveyAnswerType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            .disabled(!s.enabled)

            Section {
                HStack(spacing: 12) {
                    StatChip(label: "Total", value: "\(responses.count)")
                    StatChip(label: "Today", value: "\(responses.filter { Calendar.current.isDateInToday($0.submittedAt) }.count)")
                    StatChip(label: "Avg ★", value: averageRatingLabel)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                if !responses.isEmpty {
                    Button {
                        Haptics.tap()
                        exportCSV()
                    } label: {
                        Label("Export responses (CSV)", systemImage: "square.and.arrow.up")
                    }
                }
            } header: {
                Text("Stats")
            }

            Section {
                if responses.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title)
                            .foregroundStyle(BoothifyTheme.textMuted)
                        Text("No responses yet.")
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                        Text("Responses appear here after guests complete the post-result survey.")
                            .font(.caption2)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(responses.reversed().prefix(10)) { r in
                        SurveyResponseRow(response: r)
                    }
                }
            } header: {
                Text(responses.isEmpty ? "Latest responses" : "Latest \(min(10, responses.count)) responses")
            }
        }
        .mvpFormBackground()
        .navigationTitle("Survey")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCSVShare) {
            if let url = csvShareURL {
                ActivityShareSheet(items: [url])
            }
        }
        .alert("Export failed", isPresented: Binding(get: { csvError != nil }, set: { if !$0 { csvError = nil } })) {
            Button("OK") { csvError = nil }
        } message: { Text(csvError ?? "") }
    }

    private var averageRatingLabel: String {
        let ratings = responses.compactMap(\.rating).compactMap { $0 }
        guard !ratings.isEmpty else { return "—" }
        let avg = Double(ratings.reduce(0, +)) / Double(ratings.count)
        return String(format: "%.1f", avg)
    }
}

private struct StatChip: View {
    let label: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(.white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.8)
                .foregroundStyle(BoothifyTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glassSurface(radius: 14)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(BoothifyTheme.surfaceLine, lineWidth: 1))
    }
}

private struct SurveyResponseRow: View {
    let response: SurveyResponse

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(BoothifyTheme.surface2).frame(width: 32, height: 32)
                Image(systemName: iconForType)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(answerString)
                    .font(.body)
                    .foregroundStyle(.white)
                Text(response.submittedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(BoothifyTheme.textTertiary)
            }
            Spacer()
        }
    }

    private var iconForType: String {
        switch response.answerType {
        case .rating: "star.fill"
        case .text:   "text.bubble.fill"
        case .yesNo:  "checkmark.circle.fill"
        }
    }

    private var answerString: String {
        switch response.answerType {
        case .rating: response.rating.map { "★ \($0)/5" } ?? "—"
        case .text:   response.text ?? "—"
        case .yesNo:  response.yesNo == true ? "Yes" : "No"
        }
    }
}

/// Post-result survey sheet. Pushed by ResultView when the photo finishes.
struct PostResultSurveySheet: View {
    let settings: SurveySettings
    let onSubmit: (SurveyResponse) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 0
    @State private var text: String = ""
    @State private var yes: Bool? = nil

    var body: some View {
        ZStack {
            AtmosphericBackground()
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.title)
                        .foregroundStyle(BoothifyTheme.violet)
                    Text(settings.questionText)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 32)

                switch settings.answerType {
                case .rating:
                    HStack(spacing: 12) {
                        ForEach(1...5, id: \.self) { i in
                            Button {
                                Haptics.selection()
                                rating = i
                            } label: {
                                Image(systemName: i <= rating ? "star.fill" : "star")
                                    .font(.system(size: 36).bold())
                                    .foregroundStyle(i <= rating ? BoothifyTheme.violet : BoothifyTheme.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Rate \(i) stars")
                        }
                    }
                    if rating > 0 {
                        Text(ratingLabel(rating))
                            .font(.subheadline)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                            .transition(.opacity)
                    }
                case .text:
                    TextField("Type here…", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundStyle(.white)
                        .padding(BoothifySpacing.md)
                        .glassSurface(radius: BoothifyRadius.input)
                        .padding(.horizontal, BoothifySpacing.lg)
                case .yesNo:
                    HStack(spacing: 12) {
                        Button("Yes") { Haptics.selection(); yes = true }
                            .buttonStyle(yes == true ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
                        Button("No") { Haptics.selection(); yes = false }
                            .buttonStyle(yes == false ? AnyButtonStyle(PrimaryButtonStyle()) : AnyButtonStyle(SecondaryButtonStyle()))
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                Button("Submit") {
                    submit()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)
                .padding(.horizontal, 24)

                if !settings.required {
                    Button("Skip") { dismiss() }
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    private func ratingLabel(_ r: Int) -> String {
        switch r {
        case 1: "Sorry to hear — we'll do better."
        case 2: "Thanks for the feedback."
        case 3: "Good to know."
        case 4: "Great!"
        case 5: "Amazing — thank you!"
        default: ""
        }
    }

    private var canSubmit: Bool {
        switch settings.answerType {
        case .rating: rating > 0
        case .text:   !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .yesNo:  yes != nil
        }
    }

    private func submit() {
        let r = SurveyResponse(
            photoId: nil,
            answerType: settings.answerType,
            rating: settings.answerType == .rating ? rating : nil,
            text: settings.answerType == .text ? text : nil,
            yesNo: settings.answerType == .yesNo ? yes : nil
        )
        Haptics.notify(.success)
        onSubmit(r)
        dismiss()
    }
}

private struct AnyButtonStyle: ButtonStyle {
    private let _make: @MainActor (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) {
        self._make = { config in AnyView(style.makeBody(configuration: config)) }
    }
    func makeBody(configuration: Configuration) -> some View { _make(configuration) }
}

// MARK: - Sharing Status

struct SharingStatusView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    private var s: SharingSettings { app.settings(for: eventId).sharing }
    @State private var latestPhotoId: UUID?
    @State private var testStatus: [SharingChannel: ChannelStatus] = [:]

    enum ChannelStatus: Equatable {
        case sending, sent, failed(String)

        var label: String {
            switch self {
            case .sending: "Sending…"
            case .sent: "Sent ✓"
            case .failed(let m): m
            }
        }
        var color: Color {
            switch self {
            case .sending: BoothifyTheme.violet
            case .sent: BoothifyTheme.emerald
            case .failed: BoothifyTheme.error
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(SharingChannel.allCases, id: \.self) { channel in
                    SharingChannelRow(
                        channel: channel,
                        status: status(for: channel),
                        canTest: false,
                        live: nil
                    ) {}
                }
            } header: {
                Text("Delivery channels")
            } footer: {
                Text("Status reflects local config. Test sends return with 360 clip delivery (per-channel tests against real endpoints).")
                    .font(.caption2)
            }
            .listRowBackground(GlassRowBackground())

            Section {
                TextField("test@example.com", text: app.mvpBinding(eventId: eventId, keyPath: \.sharing.testEmail))
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .textContentType(.emailAddress)
                if !s.testEmail.isEmpty && !isValidEmail(s.testEmail) {
                    Text("Invalid email format").font(.caption2).foregroundStyle(BoothifyTheme.error)
                }
                TextField("+48 500 111 222", text: app.mvpBinding(eventId: eventId, keyPath: \.sharing.testPhone))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                if !s.testPhone.isEmpty && !isValidPhone(s.testPhone) {
                    Text("Phone must be at least 7 digits").font(.caption2).foregroundStyle(BoothifyTheme.error)
                }
            } header: {
                Text("Test recipients")
            } footer: {
                Text("Used by the Send test buttons above. Saved per event.")
                    .font(.caption2)
            }
            .listRowBackground(GlassRowBackground())

        }
        .scrollContentBackground(.hidden)
        .background(AtmosphericBackground())
        .tint(BoothifyTheme.violet)
        .navigationTitle("Delivery Status")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func status(for channel: SharingChannel) -> String {
        s.enabledChannels.contains(channel) ? "Ready" : "Not configured"
    }

    private func channelHasTest(_ channel: SharingChannel) -> Bool {
        switch channel {
        case .email, .sms: true
        default: false
        }
    }

    private func isRecipientValid(_ channel: SharingChannel) -> Bool {
        switch channel {
        case .email: isValidEmail(s.testEmail)
        case .sms:   isValidPhone(s.testPhone)
        default: true
        }
    }

    private func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard let at = trimmed.firstIndex(of: "@"), at != trimmed.startIndex else { return false }
        let domain = trimmed[trimmed.index(after: at)...]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }

    private func isValidPhone(_ value: String) -> Bool {
        value.filter(\.isNumber).count >= 7
    }

}

private struct SharingChannelRow: View {
    let channel: SharingChannel
    let status: String
    let canTest: Bool
    let live: SharingStatusView.ChannelStatus?
    let test: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(BoothifyTheme.surface2)
                    .frame(width: 32, height: 32)
                Image(systemName: channel.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.label)
                    .font(.body)
                    .foregroundStyle(.white)
                Text(live?.label ?? status)
                    .font(.footnote)
                    .foregroundStyle(live?.color ?? BoothifyTheme.textTertiary)
                    .lineLimit(2)
            }
            Spacer()
            if canTest {
                Button("Send test") { test() }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                    .buttonStyle(.plain)
                    .disabled(live == .sending)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Account

struct AccountSettingsView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var confirmReset = false
    @State private var confirmSignOut = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    @State private var copiedLabel: String?

    private var event: Event? { app.event(id: eventId) }
    private var signedInEmail: String? {
        // Prefer the email Supabase issued; fall back to whatever Apple shipped
        // on first login (the only time Apple ever gives us an email).
        app.currentUser?.email ?? AppleProfileCache.cachedEmail
    }
    private var signedInName: String? {
        // BM2 — prefer the backend-issued `full_name` (AM2 column on users)
        // which now rides in the AuthSession response. Falls back to the
        // local AppleProfileCache (populated on first Apple sign-in).
        app.currentUser?.fullName ?? AppleProfileCache.cachedFullName
    }
    private var apiBaseURL: String { BoothifyAPI.shared.baseURL.absoluteString }
    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(v) (\(b))"
    }
    private var environmentLabel: String {
        let host = BoothifyAPI.shared.baseURL.host ?? ""
        if host.contains("localhost") || host.hasPrefix("127.") { return "Development" }
        if host.contains("vercel.app") { return "Staging" }
        return "Production"
    }

    var body: some View {
        List {
            // M2: surface signed-in identity. Apple's first-login email is
            // cached in AppleProfileCache so this stays populated across
            // refreshes (where Supabase may return only the user id).
            if app.isAuthenticated {
                Section("Signed in") {
                    if let name = signedInName, !name.isEmpty {
                        LabeledRowInline(title: "Name", value: name)
                    }
                    LabeledRowInline(title: "Email", value: signedInEmail ?? "—")
                    if let userId = app.currentUser?.id {
                        HStack {
                            Text("User ID").foregroundStyle(.white)
                            Spacer()
                            Text(userId)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                                .font(.system(.footnote, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                .listRowBackground(GlassRowBackground())
            }

            Section("Event") {
                LabeledRowInline(title: "Name", value: event?.name ?? "—")
                HStack {
                    Text("Slug").foregroundStyle(.white)
                    Spacer()
                    Text(event?.slug ?? "—")
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .font(.system(.footnote, design: .monospaced))
                    if event?.slug != nil {
                        Button {
                            copy(event!.slug, label: "Slug")
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(BoothifyTheme.violet)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Copy slug")
                    }
                }
                if let createdAt = event?.createdAt {
                    LabeledRowInline(title: "Created", value: createdAt.formatted(date: .abbreviated, time: .shortened))
                }
            }
            .listRowBackground(GlassRowBackground())

            Section("App") {
                LabeledRowInline(title: "Version", value: appVersion)
                LabeledRowInline(title: "Environment", value: environmentLabel)
                HStack {
                    Text("API base URL").foregroundStyle(.white)
                    Spacer()
                    Text(apiBaseURL)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button {
                        copy(apiBaseURL, label: "API URL")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundStyle(BoothifyTheme.violet)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Copy API base URL")
                }
                if let copiedLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(BoothifyTheme.emerald)
                        Text("\(copiedLabel) copied to clipboard")
                            .foregroundStyle(BoothifyTheme.emerald)
                    }
                    .font(.footnote.weight(.medium))
                    .transition(.opacity)
                }
            }
            .listRowBackground(GlassRowBackground())

            Section {
                Button(role: .destructive) {
                    Haptics.tap()
                    confirmReset = true
                } label: {
                    Label("Reset local settings for this event", systemImage: "arrow.counterclockwise")
                }
            }
            .listRowBackground(GlassRowBackground())

            // M2: account-level actions. Always available so the operator can
            // bail mid-event if the wrong Apple ID logged in.
            if app.isAuthenticated {
                Section {
                    Button {
                        Haptics.tap()
                        confirmSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(.white)
                    }
                }
                .listRowBackground(GlassRowBackground())

                Section {
                    Button(role: .destructive) {
                        Haptics.tap()
                        confirmDelete = true
                    } label: {
                        if deleting {
                            HStack(spacing: 8) {
                                ProgressView().tint(BoothifyTheme.error)
                                Text("Deleting…")
                            }
                        } else {
                            Label("Delete account", systemImage: "trash")
                        }
                    }
                    .disabled(deleting)
                    if let deleteError {
                        Text(deleteError)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                    }
                } footer: {
                    Text("Removes your Boothify account and all associated events, photos and 360 recordings from our servers. This cannot be undone.")
                }
                .listRowBackground(GlassRowBackground())
            }
        }
        .scrollContentBackground(.hidden)
        .background(AtmosphericBackground())
        .tint(BoothifyTheme.violet)
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset settings?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) {
                app.resetSettings(for: eventId)
                Haptics.notify(.success)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All local settings for this event will be restored to defaults. Photos and event data on the backend are not affected.")
        }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) {
                app.signOut()
                Haptics.notify(.success)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in with Apple again to access your events.")
        }
        .alert("Delete account?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                deleteAccount()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes your account and all events from Boothify. You can't undo this.")
        }
    }

    private func deleteAccount() {
        guard let token = app.session?.accessToken else {
            // No session — just clean up locally.
            app.signOut()
            return
        }
        deleting = true
        deleteError = nil
        Task {
            do {
                try await AuthClient.shared.deleteAccount(accessToken: token)
                app.signOut()
                Haptics.notify(.success)
            } catch {
                // Backend endpoint not deployed yet (404) or transient — sign
                // them out locally either way and surface a message they can
                // act on. Apple's policy is satisfied by the LOCAL deletion +
                // a path to escalate.
                let apiErr = (error as? APIError)?.errorDescription ?? error.localizedDescription
                deleteError = "Signed out locally — to fully delete your data email support@boothify.app. (\(apiErr))"
                app.signOut()
            }
            deleting = false
        }
    }

    private func copy(_ value: String, label: String) {
        UIPasteboard.general.string = value
        Haptics.notify(.success)
        withAnimation(.spring) { copiedLabel = label }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { copiedLabel = nil }
        }
    }
}

private struct LabeledRowInline: View {
    let title: String
    let value: String
    var monospaced: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .foregroundStyle(BoothifyTheme.textTertiary)
                .font(monospaced ? .system(.footnote, design: .monospaced) : .footnote)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - Color hex helper

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&int)
        let r, g, b: Double
        switch trimmed.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255
            g = Double((int >> 8) & 0xFF) / 255
            b = Double(int & 0xFF) / 255
        default:
            r = 0; g = 0; b = 0
        }
        self.init(red: r, green: g, blue: b)
    }
}
