import SwiftUI

/// 360 AI Booth event launcher. Mirrors `PhotoboothLandingView` for parity but
/// routes into the dedicated 360 flow (recording → processing → result) on
/// create. Recent events list is the shared `app.events` list — operators see
/// all of their events regardless of which mode they were created in.
struct Booth360LandingView: View {
    @Environment(AppState.self) private var app

    @State private var eventName: String = ""
    @State private var creating: Bool = false
    @State private var createError: String? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: BoothifySpacing.lg) {
                    headerBlock

                    newSessionCard

                    if let topErr = app.topLevelError {
                        Text(topErr)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                            .multilineTextAlignment(.center)
                    }

                    recentEventsSection
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.top, BoothifySpacing.xs)
                .padding(.bottom, BoothifySpacing.lg)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("360 AI Booth")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            CrashRestoreManager.clearActiveEvent()
            await app.loadRecentEvents()
        }
        .refreshable { await app.loadRecentEvents() }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            // Mode badge
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(BoothifyTheme.amber.opacity(0.25))
                        .frame(width: 8, height: 8)
                    Circle()
                        .fill(BoothifyTheme.amber)
                        .frame(width: 5, height: 5)
                }
                .accessibilityHidden(true)
                Text("360 mode")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.amber)
                Spacer()
                Text("BETA")
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
                    .foregroundStyle(BoothifyTheme.amber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(BoothifyTheme.amber.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.40), lineWidth: 0.8))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(BoothifyTheme.amber.opacity(0.08), in: RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.micro, style: .continuous)
                    .stroke(BoothifyTheme.amber.opacity(0.20), lineWidth: 1)
            )

            Text("Start a new 360 session")
                .font(BoothifyType.displayMedium)
                .foregroundStyle(.white)

            Text("Capture rotating 360° clips and let AI turn them into cinematic shareable videos.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - New session card

    private var newSessionCard: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            Text("NEW 360 EVENT")
                .font(.caption2.weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(BoothifyTheme.textTertiary)

            TextField(
                "",
                text: $eventName,
                prompt: Text("e.g. Anna & Tom — 360 Highlights")
                    .foregroundColor(BoothifyTheme.textMuted)
            )
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, BoothifySpacing.md)
            .frame(minHeight: 54)
            .background(BoothifyTheme.surface2, in: RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                    .stroke(
                        nameFocused ? BoothifyTheme.amber.opacity(0.60) : BoothifyTheme.surfaceLine,
                        lineWidth: nameFocused ? 1.5 : 1
                    )
            )
            .animation(.easeOut(duration: 0.18), value: nameFocused)
            .focused($nameFocused)
            .submitLabel(.go)
            .onSubmit { startSession() }
            .textInputAutocapitalization(.words)
            .disabled(creating)

            Button {
                startSession()
            } label: {
                HStack(spacing: 8) {
                    if creating {
                        ProgressView().tint(.white)
                    }
                    Text(creating ? "Creating event…" : "Start session")
                    if !creating {
                        Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(creating || eventName.trimmingCharacters(in: .whitespaces).count < 2)
            .opacity(eventName.trimmingCharacters(in: .whitespaces).count < 2 ? 0.50 : 1)

            if let createError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption.weight(.semibold))
                    Text(createError)
                        .font(.footnote)
                }
                .foregroundStyle(BoothifyTheme.error)
            }
        }
        .padding(BoothifySpacing.md)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.20), radius: 12, y: 6)
    }

    // MARK: - Recent events

    @ViewBuilder
    private var recentEventsSection: some View {
        if app.isLoadingEvents && app.events.isEmpty {
            ProgressView().tint(BoothifyTheme.amber).padding(.top, 20)
        } else if app.events.isEmpty {
            Booth360EmptyState()
        } else {
            VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
                HStack {
                    Text("RECENT EVENTS")
                        .font(.caption2.weight(.semibold))
                        .kerning(1.4)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                    Spacer()
                    Text("\(app.events.count) \(app.events.count == 1 ? "event" : "events")")
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textMuted)
                }
                .padding(.horizontal, 2)

                VStack(spacing: BoothifySpacing.sm) {
                    ForEach(app.events) { event in
                        Booth360EventRow(event: event, jobs: app.jobs(for: event.id)) {
                            Haptics.tap()
                            app.push(.booth360EventHub(eventId: event.id))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func startSession() {
        let trimmed = eventName.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        creating = true
        createError = nil
        nameFocused = false
        Haptics.tap(.medium)
        Task {
            do {
                let event = try await app.createEvent(name: trimmed)
                Haptics.notify(.success)
                creating = false
                eventName = ""
                app.push(.booth360EventHub(eventId: event.id))
                app.push(.booth360Recording(eventId: event.id))
            } catch {
                Haptics.notify(.error)
                createError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                creating = false
            }
        }
    }
}

// MARK: - Row & empty state

struct Booth360EventRow: View {
    let event: Event
    let jobs: [Booth360Job]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BoothifySpacing.sm) {
                thumbnail
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                            .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: BoothifySpacing.sm)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .padding(BoothifySpacing.sm + 4)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var subtitle: String {
        let completed = jobs.filter { $0.status == .completed }.count
        let videos = "\(completed) \(completed == 1 ? "video" : "videos")"
        let date = event.createdAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(videos) · \(date)"
    }

    @ViewBuilder
    private var thumbnail: some View {
        ZStack {
            BoothifyTheme.surface2
            Image(systemName: "video.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(BoothifyTheme.amber.opacity(0.80))
        }
    }
}

struct Booth360EmptyState: View {
    var body: some View {
        VStack(spacing: BoothifySpacing.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                    .fill(BoothifyTheme.surface2)
                    .frame(width: 60, height: 60)
                Image(systemName: "video.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.amber.opacity(0.70))
            }
            .accessibilityHidden(true)
            Text("No 360 sessions yet")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
            Text("Create your first event to start capturing 360° clips.")
                .font(.caption)
                .foregroundStyle(BoothifyTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BoothifySpacing.xl)
    }
}

#Preview {
    NavigationStack {
        Booth360LandingView()
    }
    .environment(AppState())
}
