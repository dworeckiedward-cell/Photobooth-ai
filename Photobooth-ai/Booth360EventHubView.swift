import SwiftUI
import UIKit

/// Operator console for a single 360 AI Booth event. Mirrors `EventHubView`
/// but with 360-specific copy + data sources. Primary CTA opens the recording
/// screen; recent recordings, stats, and share live below.
struct Booth360EventHubView: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var sharePresented: Bool = false
    @State private var copiedLink: Bool = false

    private var event: Event? { app.event(id: eventId) }
    private var jobs: [Booth360Job] { app.jobs(for: eventId) }
    private var completed: [Booth360Job] { jobs.filter { $0.status == .completed } }
    private var processing: [Booth360Job] { jobs.filter { !$0.status.isTerminal } }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    if event != nil {
                        compactHeader
                        primaryCard
                        CloudStatusPanel(eventId: eventId)
                        recentRecordingsSection
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
                }
            }
        }
        .navigationTitle(event?.name ?? "Event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    app.push(.settings360Hub(eventId: eventId))
                } label: {
                    Image(systemName: "gearshape.fill")
                }
                .accessibilityLabel("360 settings")
            }
        }
        .task(id: eventId) {
            // RA2 — stash for crash-restore (cleared on intentional back).
            CrashRestoreManager.setActiveEvent(eventId)
            if let slug = event?.slug {
                await app.refreshEvent(slug: slug)
            }
        }
        .sheet(isPresented: $sharePresented) {
            if let url = guestShareURL() {
                ShareSheet(items: [url])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header

    private var compactHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(BoothifyTheme.amber.opacity(0.4))
                        .frame(width: 10, height: 10)
                        .scaleEffect(1.2)
                        .opacity(0.6)
                    Circle()
                        .fill(BoothifyTheme.amber)
                        .frame(width: 8, height: 8)
                }
                .accessibilityHidden(true)
                Text("360 event")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BoothifyTheme.surface1, in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.surfaceLine, lineWidth: 1))

            Spacer()

            Text(summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(BoothifyTheme.textTertiary)
        }
        .padding(.top, 2)
    }

    private var summary: String {
        if jobs.isEmpty { return "No recordings yet" }
        return "\(jobs.count) recordings · \(completed.count) ready"
    }

    // MARK: - Primary CTA

    private var primaryCard: some View {
        Button {
            guard let event else { return }
            Haptics.tap(.medium)
            app.push(.booth360Recording(eventId: event.id))
        } label: {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(Color.black)
                    .overlay {
                        Image("Mode_360")
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
                            colors: [BoothifyTheme.amber.opacity(0.45), .clear],
                            startPoint: .bottom, endPoint: .center
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        HStack {
                            Image(systemName: "video.fill")
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
                                Image(systemName: "sparkles")
                                    .font(.system(size: 10, weight: .bold))
                                Text("BETA")
                                    .font(.system(size: 10, weight: .bold))
                                    .kerning(0.6)
                            }
                            .foregroundStyle(BoothifyTheme.amber)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(BoothifyTheme.amber.opacity(0.18), in: Capsule())
                            .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.55), lineWidth: 0.8))
                        }
                        .padding(18)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("360 AI Booth")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
                    Text("Record a rotating clip — AI handles slow-mo, effects, and the share page.")
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
            .shadow(color: BoothifyTheme.amber.opacity(0.30), radius: 22, y: 12)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("360 AI Booth. Start session. Record a rotating clip.")
    }

    // MARK: - Recent recordings

    @ViewBuilder
    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Recent recordings", systemImage: "video.bubble.left")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if !jobs.isEmpty {
                    Text("\(jobs.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
            }

            if jobs.isEmpty {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(BoothifyTheme.surface2)
                            .frame(width: 44, height: 44)
                        Image(systemName: "tray")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(BoothifyTheme.textMuted)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No recordings yet")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Start a session to create the first 360 clip.")
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(jobs.prefix(3)) { job in
                        Button {
                            Haptics.tap()
                            if job.status == .completed {
                                app.push(.booth360Result(jobId: job.id))
                            } else if !job.status.isTerminal {
                                app.push(.booth360Processing(jobId: job.id))
                            }
                        } label: {
                            jobThumb(job: job)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                        // QW6 — VoiceOver: surface status + a hint of when
                        // it was recorded so the operator can pick a take
                        // from a long queue with their eyes off the screen.
                        .accessibilityLabel("360 recording, status: \(job.status.label)")
                        .accessibilityHint(job.status == .completed
                                           ? "Opens the result"
                                           : "Opens the processing screen")
                    }
                    if jobs.count < 3 {
                        ForEach(0..<(3 - jobs.count), id: \.self) { _ in
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

    @ViewBuilder
    private func jobThumb(job: Booth360Job) -> some View {
        VStack(spacing: 6) {
            ZStack {
                LinearGradient(
                    colors: [BoothifyTheme.amber.opacity(0.55), BoothifyTheme.fuchsia.opacity(0.45)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                if !job.status.isTerminal {
                    ProgressView().tint(.white)
                } else if job.status == .completed {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )

            HStack(spacing: 4) {
                Circle().fill(statusTint(job: job)).frame(width: 5, height: 5)
                Text(statusLabel(job: job))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusTint(job: job))
                    .lineLimit(1)
            }
        }
    }

    private func statusLabel(job: Booth360Job) -> String {
        switch job.status {
        case .completed: "Ready"
        case .failed:    "Failed"
        default:         "Processing"
        }
    }

    private func statusTint(job: Booth360Job) -> Color {
        switch job.status {
        case .completed: BoothifyTheme.emerald
        case .failed:    .red
        default:         BoothifyTheme.amber
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let zero = jobs.isEmpty
        return HStack(spacing: 10) {
            StatTile(label: "Recordings", value: "\(jobs.count)", tint: BoothifyTheme.amber, muted: zero)
            StatTile(label: "Ready", value: "\(completed.count)", tint: BoothifyTheme.emerald, muted: zero)
            StatTile(label: "Processing", value: "\(processing.count)", tint: BoothifyTheme.violet, muted: zero)
        }
        .opacity(zero ? 0.65 : 1.0)
    }

    // MARK: - Share

    private var shareEventSection: some View {
        let url = guestShareURL()
        let hasUrl = url != nil

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(BoothifyTheme.surface2)
                        .frame(width: 40, height: 40)
                    Image(systemName: "link")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(hasUrl ? BoothifyTheme.amber : BoothifyTheme.textMuted)
                }
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
                        Text("Available after the first finished recording.")
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    guard url != nil else { return }
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

    // Temporary fallback: 360 events share the latest completed render's
    // `publicShareURL` until `/e/<event-slug>` event landing page exists.
    private func guestShareURL() -> URL? {
        completed.first?.publicShareURL
    }
}

// MARK: - Tiny components

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
        Booth360EventHubView(eventId: UUID())
    }
    .environment(AppState())
}
