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

    // MARK: - Kiosk Mode (ported from the photo hub — blueprint 4.D/5)

    private var kioskButton: some View {
        Button {
            guard let event else { return }
            Haptics.tap(.medium)
            app.enterKiosk(eventId: event.id)
        } label: {
            HStack(spacing: BoothifySpacing.sm) {
                Image(systemName: "lock.display")
                    .font(.body.weight(.semibold))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Start Kiosk Mode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Hand the device to guests — locks to the booth")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .foregroundStyle(BoothifyTheme.amber)
            .padding(BoothifySpacing.md)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("Locks the app into the guest 360 booth for this event")
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: BoothifySpacing.md) {
                    if event != nil {
                        compactHeader
                        if let warning = PerfBudget.evaluate(settings: app.settings(for: eventId)).operatorMessage {
                            HStack(spacing: BoothifySpacing.sm) {
                                Image(systemName: "gauge.with.needle")
                                    .font(.body.weight(.semibold))
                                Text(warning)
                                    .font(.caption)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(BoothifyTheme.amber)
                            .padding(BoothifySpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BoothifyTheme.amber.opacity(0.10), in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                                    .stroke(BoothifyTheme.amber.opacity(0.30), lineWidth: 1)
                            )
                            .accessibilityLabel("Performance warning: \(warning)")
                        }
                        primaryCard
                        kioskButton
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
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.bottom, BoothifySpacing.xl)
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
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("360 settings")
            }
        }
        .task(id: eventId) {
            CrashRestoreManager.setActiveEvent(eventId)
            if let slug = event?.slug {
                await app.refreshEvent(slug: slug)
                await app.hydrateJobs(forEvent: eventId, slug: slug)
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
        HStack(spacing: BoothifySpacing.sm) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(BoothifyTheme.amber.opacity(0.25))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(BoothifyTheme.amber)
                        .frame(width: 6, height: 6)
                }
                .accessibilityHidden(true)
                Text("360 event")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.amber)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BoothifyTheme.amber.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.30), lineWidth: 1))

            Spacer()

            Text(summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(BoothifyTheme.textTertiary)
        }
        .padding(.top, BoothifySpacing.xs)
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
                    // Gradients on photo/media content — permitted by design system
                    .overlay {
                        LinearGradient(
                            colors: [.black.opacity(0.30), .black.opacity(0.55), .black.opacity(0.90)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    }
                    .overlay(alignment: .topLeading) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                                    .fill(Color.black.opacity(0.45))
                                    .frame(width: 48, height: 48)
                                Image(systemName: "video.fill")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .shadow(color: .black.opacity(0.5), radius: 8, y: 4)
                            .accessibilityHidden(true)

                            Spacer()

                            HStack(spacing: 4) {
                                Image(systemName: "sparkles")
                                    .font(.caption2.weight(.bold))
                                Text("BETA")
                                    .font(.caption2.weight(.bold))
                                    .kerning(0.6)
                            }
                            .foregroundStyle(BoothifyTheme.amber)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(BoothifyTheme.amber.opacity(0.18), in: Capsule())
                            .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.55), lineWidth: 0.8))
                        }
                        .padding(BoothifySpacing.md)
                    }

                VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
                    Text("360 AI Booth")
                        .font(BoothifyType.title)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                    Text("Record a rotating clip — AI handles slow-mo, effects, and the share page.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text("Start session")
                            .font(.body.weight(.semibold))
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(BoothifyTheme.amber)
                    .padding(.top, 4)
                }
                .padding(BoothifySpacing.md)
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
        .accessibilityLabel("360 AI Booth. Start session. Record a rotating clip.")
    }

    // MARK: - Recent recordings

    @ViewBuilder
    private var recentRecordingsSection: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "video.bubble.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.amber)
                    Text("Recent recordings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if !jobs.isEmpty {
                    Text("\(jobs.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(BoothifyTheme.surface2, in: Capsule())
                }
            }

            if jobs.isEmpty {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
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
                .padding(.vertical, 4)
            } else {
                HStack(spacing: BoothifySpacing.sm) {
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
        .padding(BoothifySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    @ViewBuilder
    private func jobThumb(job: Booth360Job) -> some View {
        VStack(spacing: 6) {
            ZStack {
                BoothifyTheme.surface2
                if !job.status.isTerminal {
                    ProgressView().tint(BoothifyTheme.amber)
                } else if job.status == .completed {
                    Image(systemName: "play.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                    .stroke(statusTint(job: job).opacity(job.status == .completed ? 0.35 : 0.20), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.20), radius: 4, y: 2)

            HStack(spacing: 4) {
                Circle().fill(statusTint(job: job)).frame(width: 5, height: 5)
                Text(statusLabel(job: job))
                    .font(.caption2.weight(.semibold))
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
        case .failed:    BoothifyTheme.error
        default:         BoothifyTheme.amber
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        let zero = jobs.isEmpty
        return HStack(spacing: BoothifySpacing.sm) {
            StatTile(label: "Recordings", value: "\(jobs.count)", tint: BoothifyTheme.amber, muted: zero)
            StatTile(label: "Ready", value: "\(completed.count)", tint: BoothifyTheme.emerald, muted: zero)
            StatTile(label: "Processing", value: "\(processing.count)", tint: BoothifyTheme.violet, muted: zero)
        }
        .opacity(zero ? 0.60 : 1.0)
    }

    // MARK: - Share

    private var shareEventSection: some View {
        let url = guestShareURL()
        let hasUrl = url != nil

        return VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous)
                        .fill(BoothifyTheme.surface2)
                        .frame(width: 40, height: 40)
                    Image(systemName: "link")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(hasUrl ? BoothifyTheme.amber : BoothifyTheme.textMuted)
                }
                VStack(alignment: .leading, spacing: 3) {
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

            HStack(spacing: BoothifySpacing.sm) {
                Button {
                    Haptics.tap()
                    guard url != nil else { return }
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
                    withAnimation(BoothifyMotion.bouncy) { copiedLink = true }
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        withAnimation(BoothifyMotion.quickTap) { copiedLink = false }
                    }
                } label: {
                    Label(copiedLink ? "Copied" : "Copy", systemImage: copiedLink ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(!hasUrl)
            }
        }
        .padding(BoothifySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.section, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private func guestShareURL() -> URL? {
        completed
            .first(where: { $0.cloudUploadStatus == .uploaded })?
            .publicShareURL
    }
}

// MARK: - Tiny components

private struct EmptyThumb: View {
    var body: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                .fill(BoothifyTheme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "plus.viewfinder")
                        .font(.title3)
                        .foregroundStyle(BoothifyTheme.textMuted)
                )
                .aspectRatio(1, contentMode: .fit)
            Text("Open slot")
                .font(.caption2.weight(.semibold))
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
        VStack(spacing: 5) {
            Text(value)
                .font(.title2.bold())
                .foregroundStyle(muted ? BoothifyTheme.textSecondary : .white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(muted ? BoothifyTheme.textMuted : BoothifyTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                .stroke(muted ? BoothifyTheme.surfaceLine : tint.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
    }
}

#Preview {
    NavigationStack {
        Booth360EventHubView(eventId: UUID())
    }
    .environment(AppState())
}
