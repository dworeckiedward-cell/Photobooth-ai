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
    @State private var confirmEnd: Bool = false

    private var isCurrent: Bool { app.currentEventId == eventId }

    private var event: Event? { app.event(id: eventId) }
    private var jobs: [Booth360Job] { app.jobs(for: eventId) }
    private var completed: [Booth360Job] { jobs.filter { $0.status == .completed } }
    private var processing: [Booth360Job] { jobs.filter { !$0.status.isTerminal } }

    // MARK: - Kiosk Mode (ported from the photo hub — blueprint 4.D/5)

    private var kioskButton: some View {
        // Light floating row — one thin glass line, not a boxed card.
        Button {
            guard let event else { return }
            Haptics.tap(.medium)
            app.enterKiosk(eventId: event.id)
        } label: {
            HStack(spacing: BoothifySpacing.sm + 2) {
                Image(systemName: "lock.display")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
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
            .padding(.horizontal, BoothifySpacing.md)
            .padding(.vertical, BoothifySpacing.sm + 4)
            .glassSurface(radius: BoothifyRadius.card)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Locks the app into the guest 360 booth for this event")
    }

    // MARK: - Event lifecycle (current-event marker)
    //
    // Exactly one event runs at the booth. Live event → "End event" with a
    // red confirmation; a past event → "Continue this event", which repoints
    // the live marker (implicitly ending whichever event was running).

    @ViewBuilder
    private var lifecycleSection: some View {
        if isCurrent {
            Button {
                Haptics.tap(.medium)
                confirmEnd = true
            } label: {
                HStack(spacing: BoothifySpacing.sm + 2) {
                    Image(systemName: "power")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.error)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("End event")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Closes the live session — videos and links keep working")
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.vertical, BoothifySpacing.sm + 4)
                .glassSurface(radius: BoothifyRadius.card)
            }
            .buttonStyle(.plain)
            .confirmationDialog("End this event?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End event", role: .destructive) {
                    Haptics.notify(.success)
                    app.currentEventId = nil
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The booth stops running this event. You can continue it again anytime.")
            }
        } else {
            Button {
                Haptics.notify(.success)
                // Single live marker — continuing here ends any other event.
                app.currentEventId = eventId
            } label: {
                HStack(spacing: BoothifySpacing.sm + 2) {
                    Image(systemName: "play.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.violet)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Continue this event")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Makes it the live event — any other running event ends")
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.vertical, BoothifySpacing.sm + 4)
                .background(
                    LinearGradient(
                        colors: [BoothifyTheme.violet.opacity(0.26), BoothifyTheme.violet.opacity(0.08)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                )
                .glassSurface(radius: BoothifyRadius.card)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Resumes this event and ends any other running event")
        }
    }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            ScrollView {
                // Layout redesign: the hero card is the one dominant; kiosk is
                // a light row, recordings float without a wrapper brick, stats
                // read as one airy line and the cloud panel sinks to the
                // bottom as quiet operational detail.
                VStack(spacing: BoothifySpacing.lg) {
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
                            .foregroundStyle(BoothifyTheme.violet)
                            .padding(BoothifySpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(BoothifyTheme.violet.opacity(0.10), in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                                    .stroke(BoothifyTheme.violet.opacity(0.30), lineWidth: 1)
                            )
                            .accessibilityLabel("Performance warning: \(warning)")
                        }
                        primaryCard
                        kioskButton
                        recentRecordingsSection
                        statsRow
                        shareEventSection
                        CloudStatusPanel(eventId: eventId)
                        lifecycleSection
                    } else {
                        BoothifyEmptyState(
                            icon: "calendar.badge.exclamationmark",
                            title: "Event not found",
                            subtitle: "It may have been deleted, or this link points at another account's event."
                        )
                        .padding(.top, BoothifySpacing.xl)
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
                        .fill(BoothifyTheme.violet.opacity(0.25))
                        .frame(width: 10, height: 10)
                    Circle()
                        .fill(BoothifyTheme.violet)
                        .frame(width: 6, height: 6)
                }
                .accessibilityHidden(true)
                Text(isCurrent ? "LIVE · 360 event" : "360 event")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BoothifyTheme.violet.opacity(isCurrent ? 0.18 : 0.10), in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.violet.opacity(isCurrent ? 0.50 : 0.30), lineWidth: 1))

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
                            .foregroundStyle(BoothifyTheme.violet)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(BoothifyTheme.violet.opacity(0.18), in: Capsule())
                            .overlay(Capsule().stroke(BoothifyTheme.violet.opacity(0.55), lineWidth: 0.8))
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
                    .foregroundStyle(BoothifyTheme.violet)
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
        // No wrapper brick — an eyebrow floats over thumbnails that sit
        // directly on the atmosphere. Filler "open slot" tiles removed.
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            HStack {
                Text("RECENT RECORDINGS")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.4)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                Spacer()
                if !jobs.isEmpty {
                    Text("\(jobs.count)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textTertiary)
                }
            }
            .padding(.horizontal, 2)

            if jobs.isEmpty {
                Text("No recordings yet — start a session to create the first 360 clip.")
                    .font(.caption)
                    .foregroundStyle(BoothifyTheme.textMuted)
            } else {
                HStack(alignment: .top, spacing: BoothifySpacing.sm) {
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
                        // Keep the 3-column rhythm without fake "open slot" tiles.
                        ForEach(0..<(3 - jobs.count), id: \.self) { _ in
                            Color.clear.frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func jobThumb(job: Booth360Job) -> some View {
        VStack(spacing: 6) {
            ZStack {
                BoothifyTheme.surface2
                if !job.status.isTerminal {
                    ProgressView().tint(BoothifyTheme.violet)
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
        default:         BoothifyTheme.violet
        }
    }

    // MARK: - Stats

    private var statsRow: some View {
        // One airy line of numbers separated by hairlines — not three boxes.
        let zero = jobs.isEmpty
        return HStack(spacing: 0) {
            inlineStat(label: "Recordings", value: "\(jobs.count)")
            statDivider
            inlineStat(label: "Ready", value: "\(completed.count)", tint: completed.isEmpty ? nil : BoothifyTheme.emerald)
            statDivider
            inlineStat(label: "Processing", value: "\(processing.count)", tint: processing.isEmpty ? nil : BoothifyTheme.violet)
        }
        .padding(.vertical, BoothifySpacing.xs)
        .opacity(zero ? 0.55 : 1.0)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(BoothifyTheme.surfaceLine)
            .frame(width: 0.5, height: 30)
    }

    private func inlineStat(label: String, value: String, tint: Color? = nil) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(tint ?? .white)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .kerning(0.5)
                .foregroundStyle(BoothifyTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
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
                        .foregroundStyle(hasUrl ? BoothifyTheme.violet : BoothifyTheme.textMuted)
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
        .padding(.horizontal, BoothifySpacing.md)
        .padding(.vertical, BoothifySpacing.sm + 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface(radius: BoothifyRadius.card)
    }

    private func guestShareURL() -> URL? {
        completed
            .first(where: { $0.cloudUploadStatus == .uploaded })?
            .publicShareURL
    }
}

#Preview {
    NavigationStack {
        Booth360EventHubView(eventId: UUID())
    }
    .environment(AppState())
}
