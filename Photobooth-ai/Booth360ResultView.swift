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
    @State private var copiedLink: Bool = false

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
    }

    // MARK: - Preview card (animated placeholder)

    @ViewBuilder
    private func previewCard(job: Booth360Job) -> some View {
        Group {
            if let videoURL = job.finalVideoURL,
               FileManager.default.fileExists(atPath: videoURL.path) {
                // Real recorded video (M0 passthrough or M6 transcoded).
                VideoPreviewPlayer(url: videoURL, brand: job.brandOverlay)
            } else {
                // No file yet — render the animated placeholder so the screen
                // never goes blank. M3 cloud-failure path also lands here.
                AnimatedDemoPreviewCard(
                    durationLabel: durationLabel(job: job),
                    qualityLabel: job.settingsSnapshot.videoQuality.label,
                    brand: job.brandOverlay
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

    // MARK: - Action grid (share / copy / new)
    //
    // Save-to-camera-roll is intentionally NOT shown until the real render
    // client populates `finalVideoURL`. Showing a disabled tile reads as
    // "broken feature" in a demo. It comes back when the backend lands.

    @ViewBuilder
    private func actionGrid(job: Booth360Job) -> some View {
        let hasShareURL = job.publicShareURL != nil
        HStack(spacing: 8) {
            actionTile(symbol: "square.and.arrow.up", label: "Share", enabled: hasShareURL) {
                Haptics.tap()
                if job.publicShareURL != nil { sharePresented = true }
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
                BrandOverlayLayer(settings: brand)
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
                BrandOverlayLayer(settings: brand)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) {
                anim = 1
            }
        }
    }
}

#Preview {
    NavigationStack {
        Booth360ResultView(jobId: UUID())
    }
    .environment(AppState())
}
