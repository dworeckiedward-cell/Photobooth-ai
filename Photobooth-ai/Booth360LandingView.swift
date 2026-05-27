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
                VStack(spacing: 24) {
                    headerBlock

                    newSessionCard

                    if let topErr = app.topLevelError {
                        Text(topErr)
                            .font(.footnote)
                            .foregroundStyle(.red.opacity(0.85))
                            .multilineTextAlignment(.center)
                    }

                    recentEventsSection
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("360 AI Booth")
        .navigationBarTitleDisplayMode(.inline)
        .task { await app.loadRecentEvents() }
        .refreshable { await app.loadRecentEvents() }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Start a new 360 session")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.6)
                    .foregroundStyle(BoothifyTheme.amber)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(BoothifyTheme.amber.opacity(0.18), in: Capsule())
                    .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.5), lineWidth: 0.8))
            }
            Text("Capture rotating 360° clips and let AI turn them into cinematic shareable videos.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newSessionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NEW 360 EVENT")
                .font(.caption2.weight(.semibold))
                .kerning(1.2)
                .foregroundStyle(BoothifyTheme.textTertiary)

            TextField(
                "",
                text: $eventName,
                prompt: Text("e.g. Anna & Tom — 360 Highlights")
                    .foregroundColor(.white.opacity(0.32))
            )
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 54)
            .background(BoothifyTheme.surface2)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(nameFocused ? BoothifyTheme.amber.opacity(0.55) : BoothifyTheme.surfaceLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            .opacity(eventName.trimmingCharacters(in: .whitespaces).count < 2 ? 0.55 : 1)

            if let createError {
                Text(createError)
                    .font(.footnote)
                    .foregroundStyle(.red.opacity(0.9))
            }
        }
        .padding(18)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .shadow(color: BoothifyTheme.amber.opacity(eventName.trimmingCharacters(in: .whitespaces).count >= 2 ? 0.18 : 0), radius: 14, y: 6)
        .animation(.easeOut(duration: 0.25), value: eventName.trimmingCharacters(in: .whitespaces).count >= 2)
    }

    @ViewBuilder
    private var recentEventsSection: some View {
        if app.isLoadingEvents && app.events.isEmpty {
            ProgressView().tint(BoothifyTheme.violet).padding(.top, 20)
        } else if app.events.isEmpty {
            Booth360EmptyState()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("RECENT EVENTS")
                        .font(.caption2.weight(.semibold)).kerning(1.4)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                    Spacer()
                    Text("\(app.events.count) \(app.events.count == 1 ? "event" : "events")")
                        .font(.caption2).foregroundStyle(BoothifyTheme.textMuted)
                }
                .padding(.horizontal, 2)

                VStack(spacing: 8) {
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
                // New 360 event: drop EventHub silently into the stack BEFORE the
                // recording screen so the back arrow from Recording lands on the
                // session hub, not on Landing.
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
            HStack(spacing: 12) {
                thumbnail
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
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
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .padding(12)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
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
            LinearGradient(
                colors: [BoothifyTheme.amber.opacity(0.55), BoothifyTheme.fuchsia.opacity(0.45)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "video.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

struct Booth360EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BoothifyTheme.surface2)
                    .frame(width: 60, height: 60)
                Image(systemName: "video.badge.plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
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
        .padding(.vertical, 28)
    }
}

#Preview {
    NavigationStack {
        Booth360LandingView()
    }
    .environment(AppState())
}
