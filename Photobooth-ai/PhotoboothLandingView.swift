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
    @State private var selectedTemplate: EventTemplate? = nil
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
                    heroCard
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
        .navigationTitle("AI Photobooth")
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
            Text("AI PHOTOGRAPHY")
                .font(.caption2.weight(.bold))
                .kerning(1.6)
                .foregroundStyle(BoothifyTheme.textTertiary)

            Text("Start a new event")
                .font(BoothifyType.displayMedium)
                .foregroundStyle(.white)

            Text("Create a branded booth session in seconds.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, BoothifySpacing.xs)
    }

    // MARK: - Hero / preview card

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(Color.black)
                .overlay {
                    Image("Mode_Photobooth")
                        .resizable()
                        .scaledToFill()
                }
            // Legibility gradient
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.05), location: 0),
                    .init(color: .black.opacity(0.55), location: 0.55),
                    .init(color: .black.opacity(0.92), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            // Brand wash at the floor
            LinearGradient(
                colors: [BoothifyTheme.violet.opacity(0.30), .clear],
                startPoint: .bottom, endPoint: .center
            )

            // Status pill — top-right
            VStack {
                HStack {
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(BoothifyTheme.violet).frame(width: 6, height: 6)
                        Text("LIVE READY")
                            .font(.caption2.weight(.bold))
                            .kerning(0.8)
                    }
                    .foregroundStyle(BoothifyTheme.violet)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.50), in: Capsule())
                    .overlay(Capsule().stroke(BoothifyTheme.violet.opacity(0.50), lineWidth: 0.8))
                }
                Spacer()
            }
            .padding(16)

            // Title block — bottom-left
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Photobooth")
                    .font(.system(.title, design: .default, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                Text("22 cinematic styles · instant portraits")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.70))
            }
            .padding(20)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("AI Photobooth. 22 cinematic styles, instant portraits. Live ready.")
    }

    // MARK: - Session setup card

    private var newEventCard: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.md) {
            // Card eyebrow
            HStack(spacing: BoothifySpacing.xs) {
                Image(systemName: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text("SESSION SETUP")
                    .font(.caption2.weight(.semibold))
                    .kerning(1.2)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                Spacer()
            }

            // Input group
            VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
                Text("Event name")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)

                TextField(
                    "",
                    text: $eventName,
                    prompt: Text("Anna & Tom's Wedding")
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
                            nameFocused ? BoothifyTheme.violet.opacity(0.7) : BoothifyTheme.surfaceLine,
                            lineWidth: nameFocused ? 1.5 : 1
                        )
                )
                .background(
                    RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                        .fill(BoothifyTheme.violet.opacity(nameFocused ? 0.10 : 0))
                )
                .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                .focused($nameFocused)
                .submitLabel(.go)
                .onSubmit { startSession() }
                .textInputAutocapitalization(.words)
                .disabled(creating)
                .accessibilityLabel("Event name")
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: nameFocused)

                // Template chips — fill the name AND pre-configure the event on create.
                HStack(spacing: BoothifySpacing.xs) {
                    ForEach(EventTemplate.allCases) { template in
                        EventPresetChip(label: template.label, selected: selectedTemplate == template) {
                            Haptics.tap(.light)
                            selectedTemplate = template
                            // Only seed the name if the operator hasn't typed one —
                            // never overwrite their own wording when they tap a chip
                            // for the config. Seed also replaces a prior chip's seed.
                            let typed = eventName.trimmingCharacters(in: .whitespaces)
                            if typed.isEmpty || EventTemplate.allCases.contains(where: { $0.nameSeed == typed }) {
                                eventName = template.nameSeed
                            }
                            nameFocused = true
                        }
                        .disabled(creating)
                    }
                }
                .padding(.top, 2)

                if let t = selectedTemplate {
                    Text(templateHint(t))
                        .font(.caption2)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .padding(.top, 1)
                }
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
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 20, y: 8)
    }

    // MARK: - Recent events

    @ViewBuilder
    private var recentEventsSection: some View {
        if app.isLoadingEvents && app.events.isEmpty {
            AppLoadingState(label: "Loading events…")
                .padding(.top, BoothifySpacing.lg)
        } else if app.events.isEmpty {
            compactEmptyState
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

    // Compact, quiet empty state — not a giant dead card.
    private var compactEmptyState: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            Text("RECENT EVENTS")
                .font(.caption2.weight(.semibold))
                .kerning(1.4)
                .foregroundStyle(BoothifyTheme.textTertiary)
                .padding(.horizontal, 2)

            HStack(spacing: BoothifySpacing.md) {
                Image(systemName: "calendar.badge.plus")
                    .font(.title3)
                    .foregroundStyle(BoothifyTheme.violet)
                    .frame(width: 36, height: 36)
                    .background(BoothifyTheme.violet.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("No sessions yet")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Create your first event to begin capturing AI portraits.")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(BoothifySpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func templateHint(_ t: EventTemplate) -> String {
        switch t {
        case .wedding:   return "Sets up branding + photo consent. No survey."
        case .birthday:  return "Low-friction fun: no forms, all styles."
        case .corporate: return "Lead capture survey + branding + consent."
        }
    }

    private func startSession() {
        let trimmed = eventName.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        creating = true
        createError = nil
        nameFocused = false
        Haptics.tap(.medium)
        let template = selectedTemplate
        Task {
            do {
                let event = try await app.createEvent(name: trimmed)
                // One-tap template: pre-configure the new event's settings.
                if let template {
                    let configured = template.apply(to: app.settings(for: event.id), eventName: trimmed)
                    app.updateSettings(configured, for: event.id)
                }
                Haptics.notify(.success)
                creating = false
                eventName = ""
                selectedTemplate = nil
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

// MARK: - Preset chip

private struct EventPresetChip: View {
    let label: String
    var selected: Bool = false
    let action: () -> Void
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .white : BoothifyTheme.violet)
                .padding(.horizontal, BoothifySpacing.sm + 2)
                .padding(.vertical, 7)
                .background(BoothifyTheme.violet.opacity(selected ? 1.0 : 0.14), in: Capsule())
                .overlay(Capsule().stroke(BoothifyTheme.violet.opacity(selected ? 0 : 0.32), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .scaleEffect(pressed ? 0.95 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.7), value: pressed)
        .onLongPressGesture(minimumDuration: 0, maximumDistance: 30, perform: {}, onPressingChanged: { pressed = $0 })
        .accessibilityLabel("\(label) template")
        .accessibilityHint("Names and pre-configures the event")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
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

    private var gradientPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [BoothifyTheme.violet.opacity(0.85), BoothifyTheme.violet.opacity(0.40)],
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
