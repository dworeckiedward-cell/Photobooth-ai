import SwiftUI
import UIKit
import AVKit

/// 360 AI Booth final preview. Frontend MVP: renders an animated gradient
/// "demo preview" card stand-in for the final video. Once the backend ships a
/// `finalVideoURL` we'll swap the placeholder for an `AVPlayerLayer` — every
/// share/copy/save action below already targets the real `publicShareURL`.
struct Booth360ResultView: View {
    @Environment(AppState.self) private var app
    let jobId: UUID

    @State private var sharePresented: Bool = false
    @State private var qrPresented: Bool = false
    @State private var smsPresented: Bool = false   // BM2
    @State private var copiedLink: Bool = false
    @State private var saveToast: String? = nil

    private var job: Booth360Job? { app.job(id: jobId) }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            if let job {
                // M4: fixed layout — no ScrollView. Preview fills the available
                // vertical space, metadata chips stack tightly underneath, and
                // the action / nav rows are pinned to the bottom so the operator
                // can act without scrolling during an event.
                VStack(spacing: 12) {
                    previewCard(job: job)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity)

                    metadataChips(job: job)
                        .padding(.horizontal, 16)

                    // BM1: per-job upload-status row. Hidden when uploaded
                    // (the default success state) — only surfaces when the
                    // operator needs to act or wait.
                    uploadStatusBar(job: job)
                        .padding(.horizontal, 16)

                    actionGrid(job: job)
                        .padding(.horizontal, 16)

                    bottomActions(job: job)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                }
                .padding(.top, 12)
            } else {
                VStack {
                    Spacer()
                    Text("Job not found")
                        .font(.body)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                    Spacer()
                }
            }
        }
        .navigationTitle("360 Result")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    if let id = job?.eventId {
                        app.push(.settings360Hub(eventId: id))
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("360 settings")
            }
        }
        .sheet(isPresented: $sharePresented) {
            if let url = job?.publicShareURL {
                ShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
        // IM1: QR sheet — operator points guest's phone at the screen, they
        // get the public_share_url. Detents give them a comfortable size to
        // hold up at the booth.
        .sheet(isPresented: $qrPresented) {
            if let url = job?.publicShareURL {
                Booth360QRSheet(url: url)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
        // BM2: SMS sheet (uses operator's Twilio + pings backend on success).
        .sheet(isPresented: $smsPresented) {
            if let url = job?.publicShareURL, let j = job {
                Booth360SMSSheet(jobId: j.id, eventId: j.eventId, publicURL: url)
                    .presentationDetents([.medium])
            }
        }
        // IM1: lightweight "Saved to Photos" toast over the fixed layout.
        .overlay(alignment: .top) {
            if let saveToast {
                Text(saveToast)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.75), in: Capsule())
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring, value: saveToast)
    }

    // MARK: - Preview card (animated placeholder)

    @ViewBuilder
    private func previewCard(job: Booth360Job) -> some View {
        Group {
            if let videoURL = job.finalVideoURL,
               FileManager.default.fileExists(atPath: videoURL.path) {
                // Real recorded video (M0 passthrough or M6 transcoded).
                VideoPreviewPlayer(url: videoURL, brand: job.brandOverlay, eventId: job.eventId)
            } else {
                // No file yet — render the animated placeholder so the screen
                // never goes blank. M3 cloud-failure path also lands here.
                AnimatedDemoPreviewCard(
                    durationLabel: durationLabel(job: job),
                    qualityLabel: job.settingsSnapshot.videoQuality.label,
                    brand: job.brandOverlay,
                    eventId: job.eventId
                )
            }
        }
        .aspectRatio(9.0/16.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: BoothifyTheme.amber.opacity(0.25), radius: 22, y: 12)
    }

    private func durationLabel(job: Booth360Job) -> String {
        // Slow-mo multiplier expands the perceived duration. Default speed 1.0 = raw.
        let speed = max(0.1, job.settingsSnapshot.clipSpeed)
        let perceived = job.settingsSnapshot.recordingDurationSeconds / speed
        return "\(Int(perceived.rounded()))s slow-motion video"
    }

    // MARK: - Metadata chips

    @ViewBuilder
    private func metadataChips(job: Booth360Job) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(job.settingsSnapshot.videoQuality.label, symbol: "rectangle.compress.vertical", tint: BoothifyTheme.violet)
                chip(job.settingsSnapshot.clipDirection.label, symbol: "arrow.left.arrow.right", tint: BoothifyTheme.fuchsia)
                if job.brandOverlay.rendersOnResults {
                    chip("Brand overlay", symbol: "rosette", tint: BoothifyTheme.emerald)
                }
                if let track = job.soundtrackId {
                    chip(track, symbol: "music.note", tint: BoothifyTheme.violet)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(_ label: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.caption2.weight(.bold))
            Text(label).font(.caption2.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.16), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 0.5))
    }

    // MARK: - Action grid (share / QR / copy / save / new)
    //
    // IM1: Share is now a native `ShareLink` so AirDrop, Messages, WhatsApp,
    // Mail, etc. all show up without us re-implementing each one.
    // QR is a dedicated tile that brings up the on-device generated code.
    // Save-to-Photos re-enabled because IM0 produces a real `finalVideoURL`.

    @ViewBuilder
    private func actionGrid(job: Booth360Job) -> some View {
        let hasShareURL = job.publicShareURL != nil
        let hasVideo = job.finalVideoURL != nil

        HStack(spacing: 8) {
            // Native ShareLink covers AirDrop + Messages + Mail + WhatsApp +
            // copy-to-clipboard in one sheet. Disabled when there's no URL yet.
            if let url = job.publicShareURL {
                ShareLink(item: url,
                          subject: Text("Your 360 video from Boothify"),
                          message: Text("Check out the 360 take →")) {
                    actionTileLabel(symbol: "square.and.arrow.up", label: "Share", enabled: true)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            } else {
                actionTile(symbol: "square.and.arrow.up", label: "Share", enabled: false) {}
            }

            actionTile(symbol: "qrcode", label: "QR", enabled: hasShareURL) {
                Haptics.tap()
                qrPresented = true
            }

            // BM2: SMS via operator's Twilio (M5). After successful send we
            // ping POST /api/booth360/jobs/<id>/sms so the cloud status
            // 'sent' counter (BM4 backend) is accurate.
            actionTile(symbol: "message.fill", label: "SMS", enabled: hasShareURL) {
                Haptics.tap()
                smsPresented = true
            }

            actionTile(
                symbol: copiedLink ? "checkmark" : "doc.on.doc",
                label: copiedLink ? "Copied" : "Copy link",
                enabled: hasShareURL
            ) {
                Haptics.notify(.success)
                if let url = job.publicShareURL {
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation(.spring) { copiedLink = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation { copiedLink = false }
                    }
                }
            }

            actionTile(symbol: "arrow.down.to.line", label: "Save", enabled: hasVideo) {
                Haptics.tap()
                if let url = job.finalVideoURL { saveVideoToLibrary(url) }
            }

            actionTile(symbol: "video.badge.plus", label: "New", enabled: true) {
                Haptics.tap()
                // Pop back to the 360 EventHub regardless of how many screens
                // sit between us (Processing + Result, normally).
                app.popUntil { route in
                    if case .booth360EventHub = route { return true }
                    return false
                }
            }
        }
    }

    /// Pull the label out so the ShareLink branch can render it identically
    /// to the rest of the row.
    @ViewBuilder
    private func actionTileLabel(symbol: String, label: String, enabled: Bool) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(enabled ? BoothifyTheme.amber : BoothifyTheme.textMuted)
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(enabled ? .white : BoothifyTheme.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 56)
        .padding(.vertical, 8)
        .background(BoothifyTheme.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(enabled ? 1.0 : 0.55)
    }

    /// Save the rendered .mp4 (M0 raw / IM0 montage) to Photos. Uses
    /// UISaveVideoAtPathToSavedPhotosAlbum which requires NSPhotoLibraryAdd
    /// (already declared) and the file to be local.
    private func saveVideoToLibrary(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            saveToast = "File not found"
            return
        }
        UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
        saveToast = "Saved to Photos"
        Haptics.notify(.success)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            saveToast = nil
        }
    }

    @ViewBuilder
    private func actionTile(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(enabled ? BoothifyTheme.amber : BoothifyTheme.textMuted)
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(enabled ? .white : BoothifyTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.vertical, 8)
            .background(BoothifyTheme.surface1)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(enabled ? 1.0 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: - Upload status (BM1)

    /// Visible only when there's something to communicate — uploading or
    /// failed. `.uploaded` and `.notStarted` collapse to an empty view so
    /// the happy-path Result screen isn't cluttered.
    @ViewBuilder
    private func uploadStatusBar(job: Booth360Job) -> some View {
        switch job.cloudUploadStatus {
        case .uploaded, .notStarted:
            EmptyView()
        case .uploading:
            HStack(spacing: 10) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
                    .tint(BoothifyTheme.amber)
                Text("Uploading to cloud…")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                if job.progress > 0 {
                    Text("\(Int(job.progress * 100))%")
                        .font(.footnote.monospaced())
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Spacer()
            }
            .padding(12)
            .background(BoothifyTheme.amber.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BoothifyTheme.amber.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .failed:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(.red.opacity(0.9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upload failed")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    if let err = job.cloudUploadError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button {
                    Haptics.tap()
                    Booth360UploadQueue.shared.retry(jobId: job.id, app: app)
                } label: {
                    Label("Send again", systemImage: "arrow.clockwise")
                        .font(.footnote.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BoothifyTheme.violet, in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .background(Color.red.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.red.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Bottom secondary actions

    @ViewBuilder
    private func bottomActions(job: Booth360Job) -> some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                app.popUntil { route in
                    if case .booth360EventHub = route { return true }
                    return false
                }
            } label: {
                Label("Back to event", systemImage: "chevron.left")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(SecondaryButtonStyle())

            Button {
                Haptics.tap()
                // Land on EventHub, then push a fresh recording screen.
                app.popUntil { route in
                    if case .booth360EventHub = route { return true }
                    return false
                }
                app.push(.booth360Recording(eventId: job.eventId))
            } label: {
                Label("Record again", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
        }
    }
}

// MARK: - Real video preview (M0)
//
// Plays a finished .mov file inline. Auto-starts, loops, mutes nothing —
// operator wants to QA the take immediately on the result screen. Brand
// overlay is composited on top via SwiftUI (matches the placeholder behavior);
// M6 will bake the overlay into the file itself.

private struct VideoPreviewPlayer: View {
    let url: URL
    let brand: BrandOverlaySettings
    let eventId: UUID

    @State private var player: AVPlayer? = nil
    @State private var loopObserver: NSObjectProtocol? = nil

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player)
                    .disabled(false)
            } else {
                Color.black
            }
            if brand.rendersOnResults {
                // M7: pass eventId so .uploaded source can resolve from disk.
                BrandOverlayLayer(settings: brand, eventId: eventId)
            }
        }
        .onAppear { setup() }
        .onDisappear { teardown() }
    }

    private func setup() {
        let item = AVPlayerItem(url: url)
        let p = AVPlayer(playerItem: item)
        p.isMuted = false
        player = p

        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { _ in
            p.seek(to: .zero)
            p.play()
        }
        p.play()
    }

    private func teardown() {
        if let loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
        }
        loopObserver = nil
        player?.pause()
        player = nil
    }
}

// MARK: - Animated demo preview card

private struct AnimatedDemoPreviewCard: View {
    let durationLabel: String
    let qualityLabel: String
    let brand: BrandOverlaySettings
    let eventId: UUID

    @State private var anim: CGFloat = 0

    var body: some View {
        ZStack {
            // Sweeping gradient that loops, evoking a cinematic 360 reel
            AngularGradient(
                colors: [
                    BoothifyTheme.amber.opacity(0.75),
                    BoothifyTheme.fuchsia.opacity(0.85),
                    BoothifyTheme.violet.opacity(0.85),
                    Color(red: 0.10, green: 0.10, blue: 0.16),
                    BoothifyTheme.amber.opacity(0.75),
                ],
                center: .center
            )
            .blur(radius: 20)
            .rotationEffect(.degrees(Double(anim) * 360))

            // Vignette
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )

            // Centerpiece
            VStack(spacing: 14) {
                Spacer()
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.55), lineWidth: 2)
                        .frame(width: 78, height: 78)
                    Image(systemName: "play.fill")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: 2)
                }
                Text(durationLabel)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 4)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.caption2)
                    Text(qualityLabel)
                        .font(.caption2.weight(.bold))
                        .kerning(1.0)
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.35), in: Capsule())
                .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 0.5))
                Spacer()
            }
            .padding(.vertical, 24)

            // Brand overlay (matches the photo result rendering behavior)
            if brand.rendersOnResults {
                // M7: pass eventId so .uploaded source can resolve from disk.
                BrandOverlayLayer(settings: brand, eventId: eventId)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                anim = 1
            }
        }
    }
}

/// IM1: QR sheet for guests to scan straight off the iPad. Big code, the
/// URL printed underneath for accessibility / fallback, plus a "Copy link"
/// button for the operator in case the guest can't scan.
private struct Booth360QRSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text("Scan to get the video")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            QRCodeView(url: url)
                .frame(maxWidth: 320, maxHeight: 320)
                .padding(.horizontal, 24)

            Text(url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.horizontal, 24)

            Button {
                UIPasteboard.general.string = url.absoluteString
                Haptics.notify(.success)
                withAnimation(.spring) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    withAnimation { copied = false }
                }
            } label: {
                Label(copied ? "Copied" : "Copy link",
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(.horizontal, 24)
            .padding(.bottom, 24)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - BM2 SMS sheet
//
// Wraps the same TwilioClient flow the photo SMSSheet uses, but for 360
// jobs. On success we also fire `markBooth360SMSSent` so the backend
// status counter ticks.

private struct Booth360SMSSheet: View {
    let jobId: UUID
    let eventId: UUID
    let publicURL: URL
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var phone: String = ""
    @State private var sending: Bool = false
    @State private var sent: Bool = false
    @State private var errorMessage: String?

    private var twilioConfigured: Bool {
        TwilioClient.shared.currentCredentials()?.isConfigured == true
    }

    var body: some View {
        VStack(spacing: 18) {
            Text(sent ? "SMS sent" : "Send via SMS")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.top, 20)

            if sent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(BoothifyTheme.emerald)
                Spacer()
            } else {
                if !twilioConfigured {
                    Text("Twilio isn't connected yet. Open Email / SMS settings to add credentials.")
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                TextField("+48 500 111 222", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(BoothifyTheme.surface1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 24)
                    .foregroundStyle(.white)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }

                Button {
                    send()
                } label: {
                    Text(sending ? "Sending…" : "Send")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(sending || phone.filter(\.isNumber).count < 7 || !twilioConfigured)
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func send() {
        sending = true
        errorMessage = nil
        Task {
            do {
                guard let creds = TwilioClient.shared.currentCredentials(), creds.isConfigured else {
                    throw TwilioError.notConfigured
                }
                let emailSMS = app.settings(for: eventId).emailSMS
                let event = app.event(id: eventId)
                let body = emailSMS.smsBodyTemplate
                    .replacingOccurrences(of: "{{link}}", with: publicURL.absoluteString)
                    .replacingOccurrences(of: "{{eventName}}", with: event?.name ?? "")
                let override = emailSMS.smsFromOverride.trimmingCharacters(in: .whitespaces)
                let trimmedPhone = phone.trimmingCharacters(in: .whitespaces)

                _ = try await TwilioClient.shared.sendSMS(
                    to: trimmedPhone,
                    body: body,
                    using: creds,
                    fromOverride: override.isEmpty ? nil : override
                )
                // BM2: tell backend so /api/events/<slug>/status `sent`
                // counter goes up. Fire-and-forget — operator already saw
                // success; a failed ping shouldn't bother them.
                Task.detached {
                    try? await BoothifyAPI.shared.markBooth360SMSSent(
                        jobId: jobId,
                        phone: trimmedPhone
                    )
                }
                Haptics.notify(.success)
                sent = true
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            } catch {
                Haptics.notify(.error)
                if let twilioErr = error as? TwilioError {
                    errorMessage = twilioErr.errorDescription
                } else {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
            sending = false
        }
    }
}

#Preview {
    NavigationStack {
        Booth360ResultView(jobId: UUID())
    }
    .environment(AppState())
}
