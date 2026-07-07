import SwiftUI
import UIKit
import AVKit

/// 360 AI Booth final preview. Renders the real `finalVideoURL` (produced
/// by `Booth360FFmpegRenderClient` since IM0) in an inline `VideoPreviewPlayer`
/// with brand overlay, plus an action grid for share / QR / SMS / copy /
/// save / new. Share-side actions stay disabled until the cloud upload
/// confirms (RA0 + P2).
struct Booth360ResultView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let jobId: UUID
    @State private var revealed = false

    @State private var qrPresented: Bool = false
    @State private var smsPresented: Bool = false   // BM2
    @State private var copiedLink: Bool = false

    private var job: Booth360Job? { app.job(id: jobId) }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            if let job {
                // M4: fixed layout — no ScrollView. Preview fills the available
                // vertical space, metadata chips stack tightly underneath, and
                // the action / nav rows are pinned to the bottom so the operator
                // can act without scrolling during an event.
                // Layout redesign: the hierarchy is video → QR hero → quiet
                // action whispers. The QR card IS the delivery wow moment; the
                // rest of the controls stay small and secondary — no wall of
                // equal tiles.
                VStack(spacing: BoothifySpacing.md) {
                    previewCard(job: job)
                        .padding(.horizontal, BoothifySpacing.md)
                        .frame(maxHeight: .infinity)
                        // Reveal beat — the guest's "wow" moment gets an
                        // entrance instead of just being there.
                        .scaleEffect(revealed || reduceMotion ? 1 : 0.94)
                        .opacity(revealed || reduceMotion ? 1 : 0)
                        .onAppear {
                            withAnimation(reduceMotion ? nil : BoothifyMotion.bouncy) { revealed = true }
                        }

                    metadataLine(job: job)
                        .padding(.horizontal, BoothifySpacing.md)

                    // BM1: per-job upload-status row. Hidden when uploaded
                    // (the default success state) — only surfaces when the
                    // operator needs to act or wait.
                    uploadStatusBar(job: job)
                        .padding(.horizontal, BoothifySpacing.md)

                    actionRow(job: job)
                        .padding(.horizontal, BoothifySpacing.md)

                    bottomActions(job: job)
                        .padding(.horizontal, BoothifySpacing.md)
                        .padding(.bottom, 6)
                }
                .padding(.top, BoothifySpacing.sm + 4)
            } else {
                BoothifyEmptyState(
                    icon: "video.slash",
                    title: Loc.t("This video is gone", pl: "Tego wideo już nie ma", de: "Dieses Video ist weg"),
                    subtitle: Loc.t("It may have been cleared from this device. Recent clips live in the event hub.",
                                    pl: "Mogło zostać usunięte z tego urządzenia. Ostatnie klipy znajdziesz w hubie eventu.",
                                    de: "Es wurde eventuell von diesem Gerät entfernt. Aktuelle Clips findest du im Event-Hub.")
                )
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
        // IM1: QR sheet — operator points guest's phone at the screen, they
        // get the public_share_url. Detents give them a comfortable size to
        // hold up at the booth.
        // RA0 belt-and-suspenders: require the real cloud URL even though
        // the action tile is already gated. Defense against a future caller
        // toggling `qrPresented` without checking `cloudUploadStatus`.
        .sheet(isPresented: $qrPresented) {
            // Deferred-resolve: the link is final from SIGN — show the QR even
            // mid-upload; the page resolves when the upload lands.
            if let j = job,
               let url = j.publicShareURL {
                Booth360QRSheet(url: url)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
        // BM2: SMS sheet (uses operator's Twilio + pings backend on success).
        // RA0 belt-and-suspenders gate, same reason as the QR sheet above.
        .sheet(isPresented: $smsPresented) {
            if let j = job,
               let url = j.publicShareURL {
                Booth360SMSSheet(jobId: j.id, eventId: j.eventId, publicURL: url)
                    .presentationDetents([.medium])
            }
        }
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
        .shadow(color: BoothifyTheme.violet.opacity(0.25), radius: 22, y: 12)
    }

    private func durationLabel(job: Booth360Job) -> String {
        // Slow-mo multiplier expands the perceived duration. Default speed 1.0 = raw.
        let speed = max(0.1, job.settingsSnapshot.clipSpeed)
        let perceived = job.settingsSnapshot.recordingDurationSeconds / speed
        return "\(Int(perceived.rounded()))s slow-motion video"
    }

    // MARK: - Metadata (one quiet caption, not a chip row)

    @ViewBuilder
    private func metadataLine(job: Booth360Job) -> some View {
        let parts: [String] = [
            job.settingsSnapshot.videoQuality.label,
            job.settingsSnapshot.clipDirection.label,
            job.brandOverlay.rendersOnResults ? "Brand overlay" : nil,
            job.soundtrackId,
        ].compactMap { $0 }

        Text(parts.joined(separator: " · "))
            .font(.caption2)
            .foregroundStyle(BoothifyTheme.textTertiary)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Quiet action row (share / SMS / copy / save)
    //
    // IM1: Share is a native `ShareLink` so AirDrop, Messages, WhatsApp, Mail
    // all show up without us re-implementing each one. Save-to-Photos works
    // because IM0 produces a real `finalVideoURL`. All four are deliberately
    // small — the QR card above is the hero.

    private func actionRow(job: Booth360Job) -> some View {
        let linkReady = job.publicShareURL != nil

        return HStack(spacing: BoothifySpacing.sm) {
            if linkReady, let url = job.publicShareURL {
                ShareLink(item: url,
                          subject: Text(Loc.t("Your 360 video", pl: "Twoje wideo 360", de: "Dein 360-Video")),
                          message: Text(Loc.t("Check out my 360 spin →", pl: "Zobacz mój spin 360 →", de: "Schau dir meinen 360-Spin an →"))) {
                    quietActionLabel(symbol: "square.and.arrow.up", label: Loc.t("Share", pl: "Udostępnij", de: "Teilen"), enabled: true)
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded {
                    Haptics.tap()
                    SentryClient.shared.breadcrumb(
                        "share sheet opened",
                        category: "share",
                        data: ["job_id": String(job.id.uuidString.prefix(8))]
                    )
                })
            } else {
                quietAction(symbol: "square.and.arrow.up", label: Loc.t("Share", pl: "Udostępnij", de: "Teilen"), enabled: false) {}
            }

            quietAction(symbol: "message.fill", label: Loc.t("SMS", pl: "SMS", de: "SMS"), enabled: linkReady) {
                Haptics.tap()
                SentryClient.shared.breadcrumb("sms sheet opened", category: "share",
                    data: ["job_id": String(job.id.uuidString.prefix(8))])
                smsPresented = true
            }
            quietAction(
                symbol: copiedLink ? "checkmark" : "doc.on.doc",
                label: copiedLink
                    ? Loc.t("Copied", pl: "Skopiowano", de: "Kopiert")
                    : Loc.t("Copy", pl: "Kopiuj", de: "Kopieren"),
                enabled: linkReady
            ) {
                Haptics.notify(.success)
                if let url = job.publicShareURL {
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation(BoothifyMotion.bouncy) { copiedLink = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(BoothifyMotion.quickTap) { copiedLink = false }
                    }
                }
            }
            quietAction(symbol: "qrcode", label: Loc.t("QR", pl: "QR", de: "QR"), enabled: linkReady) {
                Haptics.tap()
                SentryClient.shared.breadcrumb("qr opened", category: "share",
                    data: ["job_id": String(job.id.uuidString.prefix(8))])
                qrPresented = true
            }
        }
    }

    @ViewBuilder
    private func quietActionLabel(symbol: String, label: String, enabled: Bool) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(enabled ? .white : BoothifyTheme.textMuted)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(enabled ? BoothifyTheme.textSecondary : BoothifyTheme.textMuted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .padding(.vertical, 6)
        .glassSurface(radius: BoothifyRadius.tile)
        .opacity(enabled ? 1.0 : 0.45)
    }

    @ViewBuilder
    private func quietAction(symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            quietActionLabel(symbol: symbol, label: label, enabled: enabled)
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
                    .tint(BoothifyTheme.violet)
                Text(Loc.t("Uploading — your QR already works", pl: "Wysyłanie — Twój QR już działa", de: "Wird hochgeladen — dein QR funktioniert schon"))
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
            .background(BoothifyTheme.violet.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BoothifyTheme.violet.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        case .failed where !NetworkMonitor.shared.isConnected:
            // No network = QUEUED, not broken. The replay fires on reconnect;
            // the guest's QR still resolves once it lands. Calm, not alarming.
            HStack(spacing: BoothifySpacing.sm + 2) {
                Image(systemName: "wifi.slash")
                    .font(.body)
                    .foregroundStyle(BoothifyTheme.violet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Loc.t("Queued — offline", pl: "W kolejce — brak sieci", de: "In Warteschlange — offline"))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(Loc.t("It will upload when the connection returns. The QR keeps working.",
                               pl: "Wyśle się, gdy wróci internet. Kod QR nadal działa.",
                               de: "Wird hochgeladen, sobald die Verbindung zurück ist. Der QR-Code funktioniert weiter."))
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(BoothifySpacing.sm + 4)
            .background(BoothifyTheme.violet.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                    .stroke(BoothifyTheme.violet.opacity(0.30), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
        case .failed:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.body)
                    .foregroundStyle(BoothifyTheme.error)
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
                    Label(Loc.t("Send again", pl: "Wyślij ponownie", de: "Erneut senden"), systemImage: "arrow.clockwise")
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
            .background(BoothifyTheme.error.opacity(0.12))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BoothifyTheme.error.opacity(0.45), lineWidth: 1)
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
        // QW4 — start muted. The result screen auto-plays the moment the
        // operator opens it; un-muted audio surprises them mid-event
        // (especially during quiet ceremony moments). Native AVPlayer
        // controls let the guest unmute when they share-watch later.
        p.isMuted = true
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            // Sweeping gradient that loops, evoking a cinematic 360 reel
            AngularGradient(
                colors: [
                    BoothifyTheme.violet.opacity(0.70),
                    BoothifyTheme.violet.opacity(0.80),
                    BoothifyTheme.bg,
                    BoothifyTheme.violet.opacity(0.70),
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
                        .font(.title.weight(.bold))
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
            guard !reduceMotion else { return }
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
                Text(Loc.t("Scan to get your video", pl: "Zeskanuj i odbierz wideo", de: "Scannen und Video erhalten"))
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
                .frame(width: 44, height: 44)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            QRCodeView(url: url)
                .frame(maxWidth: 320, maxHeight: 320)
                .padding(BoothifySpacing.md)
                .glassSurface(radius: BoothifyRadius.hero)
                .glowAccent(intensity: 0.45)
                .padding(.horizontal, BoothifySpacing.lg)

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
                withAnimation(BoothifyMotion.bouncy) { copied = true }       // RA5
                Task {
                    try? await Task.sleep(for: .seconds(1.4))
                    withAnimation(BoothifyMotion.quickTap) { copied = false }
                }
            } label: {
                Label(copied ? Loc.t("Copied", pl: "Skopiowano", de: "Kopiert") : Loc.t("Copy link", pl: "Kopiuj link", de: "Link kopieren"),
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
            Text(sent ? Loc.t("SMS sent", pl: "SMS wysłany", de: "SMS gesendet") : Loc.t("Send via SMS", pl: "Wyślij SMS-em", de: "Per SMS senden"))
                .font(.title3.bold())
                .foregroundStyle(.white)
                .padding(.top, 20)

            if sent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
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
                    .glassSurface(radius: 12)
                    .padding(.horizontal, 24)
                    .foregroundStyle(.white)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.error)
                        .padding(.horizontal, 24)
                        .multilineTextAlignment(.center)
                }

                Button {
                    send()
                } label: {
                    Text(sending ? Loc.t("Sending…", pl: "Wysyłanie…", de: "Wird gesendet…") : Loc.t("Send", pl: "Wyślij", de: "Senden"))
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
                let body = DeliveryPolicy.smsBody(
                    template: emailSMS.smsBodyTemplate,
                    link: publicURL,
                    eventName: event?.name ?? ""
                )
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
                // P4 — phone number is PII; DO NOT log it. Job-id only.
                await SentryClient.shared.breadcrumb(
                    "sms sent",
                    category: "share",
                    data: ["job_id": String(jobId.uuidString.prefix(8))]
                )
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
