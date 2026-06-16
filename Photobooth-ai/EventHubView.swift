import SwiftUI
import UIKit

/// AI Photobooth event hub — focused operator control center for a single event.
///
/// Sections, top → bottom:
///   1. Compact header: "Event active" pill + capture summary (single title lives in nav bar)
///   2. Primary operational CTA: "Start AI Session"
///   3. Recent captures (3 thumbs w/ status, tap → Album/Gallery)
///   4. Stats row: Captures · Completed · Processing
///   5. Share event (latest result public URL — temporary fallback, see comment below)
///
/// Other tools (Slideshow, Guest Page link) live INSIDE the Album/Gallery flow
/// reached via the Recent captures section — not as primary cards on this screen.
struct EventHubView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventId: UUID

    @State private var recentPhotos: [Photo] = []
    @State private var totalCaptures: Int = 0
    @State private var totalCompleted: Int = 0
    @State private var totalProcessing: Int = 0
    @State private var shareSheetItems: [Any] = []
    @State private var sharePresented: Bool = false
    @State private var qrPresented: Bool = false
    @State private var copiedLink: Bool = false
    @State private var loadError: String? = nil

    // PIN gate
    @State private var pinGatePresented: Bool = false
    @State private var settingsUnlocked: Bool = false
    @State private var lastUnlockTime: Date? = nil
    @Environment(\.scenePhase) private var scenePhase

    private var event: Event? { app.event(id: eventId) }
    private var latestCompleted: Photo? {
        recentPhotos.first { $0.status == .completed }
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: BoothifySpacing.md) {
                    if event != nil {
                        compactHeader

                        primaryCard

                        CloudStatusPanel(eventId: eventId)

                        if let loadError {
                            AppEmptyState(
                                symbol: "wifi.exclamationmark",
                                symbolColor: BoothifyTheme.amber,
                                title: "Couldn't load captures",
                                subtitle: loadError,
                                actionLabel: "Retry",
                                action: {
                                    self.loadError = nil
                                    Task {
                                        if let slug = event?.slug {
                                            await loadRecent(slug: slug)
                                        }
                                    }
                                }
                            )
                        } else {
                            recentCapturesSection
                        }

                        statsRow

                        shareEventSection
                    } else {
                        AppEmptyState(
                            symbol: "calendar.badge.exclamationmark",
                            symbolColor: BoothifyTheme.error,
                            title: "Event not found",
                            subtitle: "This event may have been deleted or the link is invalid."
                        )
                        .padding(.top, BoothifySpacing.xl)
                    }
                }
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.bottom, BoothifySpacing.xxl)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable {
                if let slug = event?.slug {
                    await app.refreshEvent(slug: slug)
                    await loadRecent(slug: slug)
                }
            }
        }
        .navigationTitle(event?.name ?? "Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    let lockSettings = app.settings(for: eventId).lockPin
                    if lockSettings.enabled {
                        // Check idle timeout reset
                        if settingsUnlocked, lockSettings.idleTimeoutMinutes > 0,
                           let last = lastUnlockTime,
                           Date.now.timeIntervalSince(last) > Double(lockSettings.idleTimeoutMinutes) * 60 {
                            settingsUnlocked = false
                        }
                        if settingsUnlocked {
                            app.push(.settingsHub(eventId: eventId))
                        } else {
                            pinGatePresented = true
                        }
                    } else {
                        app.push(.settingsHub(eventId: eventId))
                    }
                } label: {
                    Image(systemName: "gearshape.fill")
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }
                .accessibilityLabel("Settings")
                .frame(width: 44, height: 44)
            }
        }
        .task(id: eventId) {
            // RA2 — stash for crash-restore. Cleared when operator backs
            // out of the hub intentionally (see PhotoboothLandingView).
            CrashRestoreManager.setActiveEvent(eventId)
            if let slug = event?.slug {
                await app.refreshEvent(slug: slug)
                await loadRecent(slug: slug)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, settingsUnlocked else { return }
            let lockSettings = app.settings(for: eventId).lockPin
            guard lockSettings.enabled, lockSettings.idleTimeoutMinutes > 0,
                  let last = lastUnlockTime,
                  Date.now.timeIntervalSince(last) > Double(lockSettings.idleTimeoutMinutes) * 60
            else { return }
            settingsUnlocked = false
        }
        .sheet(isPresented: $pinGatePresented) {
            PinGateView(eventId: eventId) {
                settingsUnlocked = true
                lastUnlockTime = .now
                pinGatePresented = false
                app.push(.settingsHub(eventId: eventId))
            }
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $sharePresented) {
            ShareSheet(items: shareSheetItems)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $qrPresented) {
            if let url = guestShareURL() {
                QRSheet(url: url.absoluteString)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(.ultraThinMaterial)
            }
        }
    }

    // MARK: - Compact header

    private var compactHeader: some View {
        HStack(spacing: BoothifySpacing.sm) {
            AppStatusPill(label: "Event active")
            Spacer()
            Text(captureSummary)
                .font(.caption.weight(.medium))
                .foregroundStyle(BoothifyTheme.textTertiary)
        }
        .padding(.top, 2)
    }

    private var captureSummary: String {
        if totalCaptures == 0 { return "No captures yet" }
        return "\(totalCaptures) captures · \(totalCompleted) completed"
    }

    // MARK: - Primary launch CTA

    private var primaryCard: some View {
        Button {
            guard let event else { return }
            Haptics.tap(.medium)
            app.push(.camera(eventId: event.id))
        } label: {
            ZStack(alignment: .bottomLeading) {
                // Media background — gradient allowed on photo/video content
                Rectangle().fill(Color.black)
                    .overlay {
                        Image("Mode_Photobooth")
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.35), .black.opacity(0.60), .black.opacity(0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                    .overlay {
                        // Violet wash on media only — not chrome
                        LinearGradient(
                            colors: [BoothifyTheme.violet.opacity(0.40), .clear],
                            startPoint: .bottom, endPoint: .center
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(alignment: .top) {
                            Image(systemName: "camera.aperture")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.40), radius: 8, y: 4)
                                .accessibilityHidden(true)
                            Spacer()
                            HStack(spacing: BoothifySpacing.xs) {
                                Circle()
                                    .fill(BoothifyTheme.emerald)
                                    .frame(width: 6, height: 6)
                                Text("LIVE")
                                    .font(.caption2.weight(.bold))
                                    .kerning(0.8)
                            }
                            .foregroundStyle(BoothifyTheme.emerald)
                            .padding(.horizontal, BoothifySpacing.sm + 2)
                            .padding(.vertical, BoothifySpacing.xs)
                            .background(BoothifyTheme.emerald.opacity(0.14), in: Capsule())
                            .overlay(Capsule().stroke(BoothifyTheme.emerald.opacity(0.40), lineWidth: 0.8))
                        }
                        .padding(BoothifySpacing.md + 2)
                    }

                VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
                    Text("AI Photobooth")
                        .font(BoothifyType.title)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.60), radius: 6, y: 2)
                    Text("Capture a guest photo, choose a style, generate the result.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                    HStack(spacing: BoothifySpacing.xs) {
                        Text("Start session")
                            .font(.subheadline.weight(.bold))
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.bold))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    .padding(.top, BoothifySpacing.xs)
                }
                .padding(BoothifySpacing.md + 2)
            }
            .frame(height: 215)
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.hero, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.40), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("AI Photobooth. Start session. Capture a guest photo, choose a style, generate the result.")
    }

    // MARK: - Recent captures

    private var recentCapturesSection: some View {
        Button {
            guard let event else { return }
            Haptics.tap()
            app.push(.gallery(eventId: event.id))
        } label: {
            VStack(alignment: .leading, spacing: BoothifySpacing.md) {
                HStack {
                    Label("Recent captures", systemImage: "photo.stack")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer()
                    if !recentPhotos.isEmpty {
                        HStack(spacing: BoothifySpacing.xs) {
                            Text("Open album")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .foregroundStyle(BoothifyTheme.violet)
                    }
                }

                if recentPhotos.isEmpty {
                    HStack(spacing: BoothifySpacing.md) {
                        AppIconBadge(symbol: "photo.on.rectangle.angled", color: BoothifyTheme.textMuted, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("No captures yet")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Start a session to create the first AI portrait.")
                                .font(.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, BoothifySpacing.xs)
                } else {
                    HStack(spacing: BoothifySpacing.sm) {
                        ForEach(recentPhotos.prefix(3)) { photo in
                            RecentThumb(photo: photo)
                                .frame(maxWidth: .infinity)
                        }
                        if recentPhotos.count < 3 {
                            ForEach(0..<(3 - recentPhotos.count), id: \.self) { _ in
                                EmptyThumb()
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            .padding(BoothifySpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .boothifySurface(radius: BoothifyRadius.section)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recentPhotos.isEmpty ? "Recent captures, none yet" : "Recent captures, \(recentPhotos.count) shown, tap to open album")
    }

    // MARK: - Stats row

    private var statsRow: some View {
        let allZero = totalCaptures == 0 && totalCompleted == 0 && totalProcessing == 0
        return HStack(spacing: BoothifySpacing.sm) {
            StatTile(label: "Captures", value: "\(totalCaptures)", tint: BoothifyTheme.violet, muted: allZero)
            StatTile(label: "Completed", value: "\(totalCompleted)", tint: BoothifyTheme.emerald, muted: allZero)
            StatTile(label: "Processing", value: "\(totalProcessing)", tint: BoothifyTheme.amber, muted: allZero)
        }
        .opacity(allZero ? 0.55 : 1.0)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: allZero)
    }

    // MARK: - Share event

    private var shareEventSection: some View {
        let url = guestShareURL()
        let hasUrl = url != nil

        return AppCard(padding: BoothifySpacing.md, radius: BoothifyRadius.section) {
            VStack(alignment: .leading, spacing: BoothifySpacing.md) {
            // Header row
            HStack(spacing: BoothifySpacing.md) {
                AppIconBadge(
                    symbol: "qrcode",
                    color: hasUrl ? BoothifyTheme.violet : BoothifyTheme.textMuted,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Share latest photo")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                    if let url {
                        Text(url.absoluteString)
                            .font(.caption2.monospaced())
                            .foregroundStyle(BoothifyTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Available after the first completed capture.")
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }
                Spacer()
            }

            // Action row
            HStack(spacing: BoothifySpacing.sm) {
                Button {
                    Haptics.tap()
                    guard let url else { return }
                    shareSheetItems = [url]
                    sharePresented = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasUrl)

                Button {
                    guard let url else { return }
                    Haptics.notify(.success)
                    UIPasteboard.general.string = url.absoluteString
                    if reduceMotion {
                        copiedLink = true
                    } else {
                        withAnimation(BoothifyMotion.bouncy) { copiedLink = true }
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        if reduceMotion {
                            copiedLink = false
                        } else {
                            withAnimation(BoothifyMotion.quickTap) { copiedLink = false }
                        }
                    }
                } label: {
                    Label(copiedLink ? "Copied" : "Copy", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasUrl)

                Button {
                    Haptics.tap()
                    qrPresented = true
                } label: {
                    Label("QR", systemImage: "qrcode.viewfinder")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasUrl)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Data

    private func loadRecent(slug: String) async {
        do {
            let list = try await BoothifyAPI.shared.listEventPhotos(slug: slug, status: .all, limit: 30)
            loadError = nil
            // Show latest non-failed photos for the recent strip.
            let visible = list.photos.filter { $0.status != .failed }
            recentPhotos = visible.prefix(6).map { $0 }

            // `list.total` is the server-side count of ALL matching photos (ignoring
            // the page limit), so it stays accurate for events with 30+ captures.
            // The per-page counters (completed, processing) are derived from the
            // fetched slice, which is fine for the small-number display — if the event
            // has hundreds of photos we still show the right completed/processing ratio
            // for the most-recent batch, which is what operators care about.
            totalCaptures = list.total
            totalCompleted = list.photos.filter { $0.status == .completed }.count
            totalProcessing = list.photos.filter {
                $0.status == .generating || $0.status == .pending || $0.status == .uploaded
            }.count
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            loadError = message
        }
    }

    // Temporary fallback: shares the latest completed photo's public URL (`/p/<photoId>`)
    // until a real `/e/<event-slug>` event gallery page exists.
    // The label "Share latest photo" accurately describes what this URL points to.
    private func guestShareURL() -> URL? {
        guard let latest = latestCompleted else { return nil }
        return BoothifyAPI.shared.publicResultURL(photoId: latest.id)
    }
}

// MARK: - Recent thumbnail

private struct RecentThumb: View {
    let photo: Photo

    var body: some View {
        VStack(spacing: BoothifySpacing.xs + 2) {
            Rectangle()
                .fill(BoothifyTheme.surface2)
                .overlay {
                    if photo.status == .completed, let url = photo.generatedURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView().tint(BoothifyTheme.violet)
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure:
                                if let asset = photo.style.previewAsset { Image(asset).resizable().scaledToFill() }
                                else { photo.style.accentGradient }
                            @unknown default: Color.clear
                            }
                        }
                    } else {
                        Group {
                            if let asset = photo.style.previewAsset {
                                Image(asset).resizable().scaledToFill()
                            } else {
                                photo.style.accentGradient
                            }
                        }
                            .blur(radius: photo.status == .completed ? 0 : 6)
                            .opacity(photo.status == .completed ? 1 : 0.40)
                            .overlay {
                                if photo.status == .generating || photo.status == .pending || photo.status == .uploaded {
                                    ProgressView().tint(.white)
                                }
                            }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                )

            HStack(spacing: 3) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 5, height: 5)
                Text(statusLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }
        }
    }

    private var statusLabel: String {
        switch photo.status {
        case .completed: "Done"
        case .failed:    "Failed"
        default:         "Processing"
        }
    }

    private var statusTint: Color {
        switch photo.status {
        case .completed: BoothifyTheme.emerald
        case .failed:    BoothifyTheme.error
        default:         BoothifyTheme.amber
        }
    }
}

private struct EmptyThumb: View {
    var body: some View {
        VStack(spacing: BoothifySpacing.xs + 2) {
            RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                .fill(BoothifyTheme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .stroke(BoothifyTheme.surfaceLine.opacity(0.6), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "plus.viewfinder")
                        .font(.title3)
                        .foregroundStyle(BoothifyTheme.textMuted.opacity(0.6))
                )
                .aspectRatio(1, contentMode: .fit)
            Text("Open slot")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BoothifyTheme.textMuted.opacity(0.5))
        }
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let label: String
    let value: String
    let tint: Color
    var muted: Bool = false

    var body: some View {
        VStack(spacing: BoothifySpacing.xs) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .kerning(0.8)
                .foregroundStyle(BoothifyTheme.textMuted)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(muted ? BoothifyTheme.textSecondary : .white)
            Rectangle()
                .fill(muted ? BoothifyTheme.surfaceLine : tint.opacity(0.55))
                .frame(height: 2)
                .clipShape(Capsule())
                .padding(.horizontal, BoothifySpacing.lg)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BoothifySpacing.md)
        .padding(.horizontal, BoothifySpacing.xs)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                .stroke(muted ? BoothifyTheme.surfaceLine : tint.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
    }
}

#Preview {
    NavigationStack {
        EventHubView(eventId: UUID())
    }
    .environment(AppState())
}
