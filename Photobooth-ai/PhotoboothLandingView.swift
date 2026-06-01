import SwiftUI

/// Premium event launcher for the AI Photobooth flow. Body title is operational
/// ("Start a new event") so it doesn't duplicate the nav-bar title. Event
/// creation lives in a single glass card that pulses with a soft violet glow
/// when the input is valid. Recent events list below uses status-aware rows.
struct PhotoboothLandingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var eventName: String = ""
    @State private var creating: Bool = false
    @State private var createError: String? = nil
    @FocusState private var nameFocused: Bool

    private var isValidName: Bool {
        eventName.trimmingCharacters(in: .whitespaces).count >= 2
    }

    var body: some View {
        ZStack {
            BoothifyTheme.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: BoothifySpacing.lg) {
                    headerBlock
                    newEventCard

                    if let topErr = app.topLevelError {
                        Text(topErr)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BoothifySpacing.md)
                    }

                    recentEventsSection
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md)
                .padding(.top, BoothifySpacing.sm)
                .padding(.bottom, BoothifySpacing.lg)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Photobooth")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            CrashRestoreManager.clearActiveEvent()
            await app.loadRecentEvents()
        }
        .refreshable { await app.loadRecentEvents() }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
            HStack(spacing: BoothifySpacing.xs) {
                Image(systemName: "bolt.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text("AI PHOTOBOOTH")
                    .font(.caption2.weight(.bold))
                    .kerning(1.4)
                    .foregroundStyle(BoothifyTheme.textTertiary)
            }

            Text("Start a new event")
                .font(BoothifyType.displayMedium)
                .foregroundStyle(.white)

            Text("Create an event and start capturing AI portraits instantly.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, BoothifySpacing.xs)
    }

    // MARK: - New event card

    private var newEventCard: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.md) {
            // Card eyebrow
            HStack(spacing: BoothifySpacing.xs) {
                Image(systemName: "plus.viewfinder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text("NEW EVENT")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.2)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                Spacer()
            }

            // Divider
            Rectangle()
                .fill(BoothifyTheme.surfaceLine)
                .frame(height: 1)

            // Input group
            VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
                Text("Event name")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)

                TextField(
                    "",
                    text: $eventName,
                    prompt: Text("e.g. Anna & Tom's Wedding")
                        .foregroundColor(.white.opacity(0.28))
                )
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, BoothifySpacing.md)
                .frame(minHeight: 52)
                .background(BoothifyTheme.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .stroke(
                            nameFocused ? BoothifyTheme.violet.opacity(0.6) : BoothifyTheme.surfaceLine,
                            lineWidth: nameFocused ? 1.5 : 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.go)
                .onSubmit { startSession() }
                .textInputAutocapitalization(.words)
                .disabled(creating)
                .accessibilityLabel("Event name")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: nameFocused)
            }

            // CTA
            Button {
                startSession()
            } label: {
                HStack(spacing: BoothifySpacing.sm) {
                    if creating {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(creating ? "Creating event…" : "Start session")
                    if !creating {
                        Image(systemName: "arrow.right")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(creating || !isValidName)
            .opacity(isValidName ? 1.0 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: isValidName)

            if let createError {
                HStack(spacing: BoothifySpacing.xs) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                    Text(createError)
                        .font(.footnote)
                }
                .foregroundStyle(BoothifyTheme.error)
            }
        }
        .padding(BoothifySpacing.lg)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 20, y: 8)
    }

    // MARK: - Recent events

    @ViewBuilder
    private var recentEventsSection: some View {
        if app.isLoadingEvents && app.events.isEmpty {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(BoothifyTheme.violet)
                .padding(.top, BoothifySpacing.lg)
        } else if app.events.isEmpty {
            emptyEventsState
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
                        RecentEventRow(event: event) {
                            Haptics.tap()
                            app.push(.eventHub(eventId: event.id))
                        }
                    }
                }
            }
        }
    }

    private var emptyEventsState: some View {
        VStack(spacing: BoothifySpacing.md) {
            ZStack {
                Circle()
                    .fill(BoothifyTheme.surface2)
                    .frame(width: 72, height: 72)
                ZStack {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BoothifyTheme.violet)
                        .offset(x: 14, y: -12)
                    Image(systemName: "calendar.badge.plus")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textSecondary)
                }
            }
            .accessibilityHidden(true)

            VStack(spacing: BoothifySpacing.xs) {
                Text("No recent events yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Create your first event to begin capturing AI portraits.")
                    .font(.caption)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BoothifySpacing.xl)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BoothifySpacing.xl)
        .padding(.horizontal, BoothifySpacing.md)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.surface, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
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
                app.push(.eventHub(eventId: event.id))
                app.push(.camera(eventId: event.id))
            } catch {
                Haptics.notify(.error)
                createError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                creating = false
            }
        }
    }
}

// MARK: - Recent event row

private struct RecentEventRow: View {
    let event: Event
    let action: () -> Void

    private enum EventLifecycle {
        case inactive, expired, full, ready

        var label: String {
            switch self {
            case .inactive: "Inactive"
            case .expired:  "Expired"
            case .full:     "Full"
            case .ready:    "Ready"
            }
        }

        var tint: Color {
            switch self {
            case .inactive: BoothifyTheme.textMuted
            case .expired:  .red
            case .full:     BoothifyTheme.amber
            case .ready:    BoothifyTheme.emerald
            }
        }
    }

    private var lifecycle: EventLifecycle {
        if event.isActive == false { return .inactive }
        if let expiry = event.expiresAt, expiry < .now { return .expired }
        if let cap = event.maxPhotos, cap > 0, event.completedPhotos >= cap { return .full }
        return .ready
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: BoothifySpacing.md) {
                thumbnail
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.tile, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: BoothifySpacing.sm)
                statusPill

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(BoothifySpacing.md)
            .frame(maxWidth: .infinity)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(event.name). \(subtitle). \(lifecycle.label).")
        .accessibilityHint("Opens event")
    }

    private var statusPill: some View {
        let tint = lifecycle.tint
        return HStack(spacing: 4) {
            Circle().fill(tint).frame(width: 6, height: 6)
            Text(lifecycle.label)
                .font(.caption2.weight(.bold))
                .kerning(0.6)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, BoothifySpacing.sm)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 0.8))
    }

    private var subtitle: String {
        let photos = "\(event.completedPhotos) \(event.completedPhotos == 1 ? "photo" : "photos")"
        let date = event.createdAt.formatted(.dateTime.month(.abbreviated).day())
        return "\(photos) · \(date)"
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let urlString = event.thumbnailUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    gradientPlaceholder
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    gradientPlaceholder
                @unknown default:
                    gradientPlaceholder
                }
            }
        } else {
            gradientPlaceholder
        }
    }

    /// Gradient is on media/photo content — permitted by design system.
    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [BoothifyTheme.violet.opacity(0.85), BoothifyTheme.fuchsia.opacity(0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Image(systemName: "camera.aperture")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

#Preview {
    NavigationStack {
        PhotoboothLandingView()
    }
    .environment(AppState())
}
