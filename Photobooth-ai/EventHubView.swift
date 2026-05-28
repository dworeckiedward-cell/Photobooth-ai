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
    let eventId: UUID

    @State private var recentPhotos: [Photo] = []
    @State private var totalCaptures: Int = 0
    @State private var totalCompleted: Int = 0
    @State private var totalProcessing: Int = 0
    @State private var shareSheetItems: [Any] = []
    @State private var sharePresented: Bool = false
    @State private var qrPresented: Bool = false
    @State private var copiedLink: Bool = false

    private var event: Event? { app.event(id: eventId) }
    private var latestCompleted: Photo? {
        recentPhotos.first { $0.status == .completed }
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    if event != nil {
                        compactHeader

                        primaryCard

                        CloudStatusPanel(eventId: eventId)

                        recentCapturesSection

                        statsRow

                        shareEventSection
                    } else {
                        Text("Event not found")
                            .font(.body)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                            .padding(.top, 40)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 36)
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
                    app.push(.settingsHub(eventId: eventId))
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("Settings")
            }
        }
        .task(id: eventId) {
            if let slug = event?.slug {
                await app.refreshEvent(slug: slug)
                await loadRecent(slug: slug)
            }
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
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(BoothifyTheme.emerald.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .scaleEffect(1.2)
                        .opacity(0.6)
                    Circle()
                        .fill(BoothifyTheme.emerald)
                        .frame(width: 8, height: 8)
                }
                .accessibilityHidden(true)
                Text("Event active")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BoothifyTheme.surface1, in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.surfaceLine, lineWidth: 1))

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
                Rectangle().fill(Color.black)
                    .overlay {
                        Image("Mode_Photobooth")
                            .resizable()
                            .scaledToFill()
                    }
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.45), .black.opacity(0.65), .black.opacity(0.92)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                    .overlay {
                        LinearGradient(
                            colors: [BoothifyTheme.violet.opacity(0.50), .clear],
                            startPoint: .bottom, endPoint: .center
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        HStack(alignment: .top) {
                            Image(systemName: "camera.aperture")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.white.opacity(0.30), lineWidth: 1)
                                )
                                .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                                .accessibilityHidden(true)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(BoothifyTheme.emerald)
                                    .frame(width: 7, height: 7)
                                Text("LIVE")
                                    .font(.system(size: 10, weight: .bold))
                                    .kerning(0.6)
                            }
                            .foregroundStyle(BoothifyTheme.emerald)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(BoothifyTheme.emerald.opacity(0.18), in: Capsule())
                            .overlay(Capsule().stroke(BoothifyTheme.emerald.opacity(0.55), lineWidth: 0.8))
                        }
                        .padding(18)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("AI Photobooth")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                    Text("Capture a guest photo, choose a style, generate the result.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("Start session")
                            .font(.body.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 1)
                    .padding(.top, 4)
                }
                .padding(18)
            }
            .frame(height: 215)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: BoothifyTheme.violet.opacity(0.32), radius: 22, y: 12)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Recent captures", systemImage: "photo.stack")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if !recentPhotos.isEmpty {
                        HStack(spacing: 4) {
                            Text("Open album")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(BoothifyTheme.violet)
                    }
                }

                if recentPhotos.isEmpty {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(BoothifyTheme.surface2)
                                .frame(width: 44, height: 44)
                            Image(systemName: "tray")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(BoothifyTheme.textMuted)
                        }
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No captures yet")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            Text("Start a session to create the first result.")
                                .font(.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 2)
                } else {
                    HStack(spacing: 8) {
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
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(recentPhotos.isEmpty ? "Recent captures, none yet" : "Recent captures, \(recentPhotos.count) shown, tap to open album")
    }

    // MARK: - Stats row

    private var statsRow: some View {
        let allZero = totalCaptures == 0 && totalCompleted == 0 && totalProcessing == 0
        return HStack(spacing: 10) {
            StatTile(label: "Captures", value: "\(totalCaptures)", tint: BoothifyTheme.violet, muted: allZero)
            StatTile(label: "Completed", value: "\(totalCompleted)", tint: BoothifyTheme.emerald, muted: allZero)
            StatTile(label: "Processing", value: "\(totalProcessing)", tint: BoothifyTheme.amber, muted: allZero)
        }
        .opacity(allZero ? 0.65 : 1.0)
    }

    // MARK: - Share event

    private var shareEventSection: some View {
        let url = guestShareURL()
        let hasUrl = url != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BoothifyTheme.surface2)
                        .frame(width: 40, height: 40)
                    Image(systemName: "qrcode")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(hasUrl ? BoothifyTheme.violet : BoothifyTheme.textMuted)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Share event")
                        .font(.subheadline.weight(.semibold))
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

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    guard let url else { return }
                    shareSheetItems = [url]
                    sharePresented = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasUrl)

                Button {
                    guard let url else { return }
                    Haptics.notify(.success)
                    UIPasteboard.general.string = url.absoluteString
                    withAnimation(.spring) { copiedLink = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation { copiedLink = false }
                    }
                } label: {
                    Label(copiedLink ? "Copied" : "Copy", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
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
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasUrl)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
    }

    // MARK: - Data

    private func loadRecent(slug: String) async {
        do {
            let list = try await BoothifyAPI.shared.listEventPhotos(slug: slug, status: .all, limit: 30)
            // Show latest 3 in any non-failed state so operators can see processing items too.
            let visible = list.photos.filter { $0.status != .failed }
            recentPhotos = visible.prefix(6).map { $0 }
            totalCaptures = list.photos.count
            totalCompleted = list.photos.filter { $0.status == .completed }.count
            totalProcessing = list.photos.filter {
                $0.status == .generating || $0.status == .pending || $0.status == .uploaded
            }.count
        } catch {
            // Silent — empty states already cover the no-data case.
        }
    }

    // Temporary fallback: Share event currently uses the latest completed photo's
    // public URL (`/p/<photoId>`) until `/e/<event-slug>` event landing page exists.
    // The UX label stays "Share event" on purpose — that's what operators understand.
    private func guestShareURL() -> URL? {
        guard let latest = latestCompleted else { return nil }
        return BoothifyAPI.shared.publicResultURL(photoId: latest.id)
    }
}

// MARK: - Recent thumbnail

private struct RecentThumb: View {
    let photo: Photo

    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(BoothifyTheme.surface2)
                .overlay {
                    if photo.status == .completed, let url = photo.generatedURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty: ProgressView().tint(BoothifyTheme.violet)
                            case .success(let img): img.resizable().scaledToFill()
                            case .failure: Image(photo.style.previewAsset).resizable().scaledToFill()
                            @unknown default: Color.clear
                            }
                        }
                    } else {
                        Image(photo.style.previewAsset)
                            .resizable()
                            .scaledToFill()
                            .blur(radius: photo.status == .completed ? 0 : 6)
                            .opacity(photo.status == .completed ? 1 : 0.45)
                            .overlay {
                                if photo.status == .generating || photo.status == .pending || photo.status == .uploaded {
                                    ProgressView().tint(.white)
                                }
                            }
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                )

            HStack(spacing: 4) {
                Circle()
                    .fill(statusTint)
                    .frame(width: 5, height: 5)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusTint)
                    .lineLimit(1)
            }
        }
    }

    private var statusLabel: String {
        switch photo.status {
        case .completed: "Completed"
        case .failed:    "Failed"
        default:         "Processing"
        }
    }

    private var statusTint: Color {
        switch photo.status {
        case .completed: BoothifyTheme.emerald
        case .failed:    .red
        default:         BoothifyTheme.amber
        }
    }
}

private struct EmptyThumb: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(BoothifyTheme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "plus.viewfinder")
                        .font(.title3)
                        .foregroundStyle(BoothifyTheme.textMuted)
                )
                .aspectRatio(1, contentMode: .fit)
            Text("Open slot")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(BoothifyTheme.textMuted)
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
        VStack(spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(BoothifyTheme.textTertiary)
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(muted ? BoothifyTheme.textSecondary : .white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(muted ? BoothifyTheme.surfaceLine : tint.opacity(0.30), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        EventHubView(eventId: UUID())
    }
    .environment(AppState())
}
