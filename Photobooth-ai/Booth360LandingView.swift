import SwiftUI

/// 360 AI Booth home — bento composition. A designed greeting header replaces
/// the nav title, then a 2-column bento grid: the glowing "Start a new
/// session" hero (tap → inline create zone), a live booth-status tile,
/// two stat tiles fed by local job data, and the latest event as a wide row
/// (routes to its hub). All prior functions are preserved: create-event with
/// 1-tap templates, recent-events loading, error surfacing.
struct Booth360LandingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var eventName: String = ""
    @State private var creating: Bool = false
    @State private var createError: String? = nil
    @State private var selectedTemplate: EventTemplate? = nil
    @State private var createExpanded: Bool = false
    @FocusState private var nameFocused: Bool

    // MARK: - Data

    private var operatorName: String {
        app.currentUser?.fullName ?? "Operator"
    }

    private var allJobs: [Booth360Job] { Array(app.booth360Jobs.values) }

    private var spinsCaptured: Int {
        allJobs.filter { $0.status == .completed }.count
    }

    /// Share of finished spins that reached the cloud. Nil until there is
    /// at least one finished spin — the tile shows a quiet placeholder.
    private var deliveredPercent: Int? {
        let done = allJobs.filter { $0.status == .completed }
        guard !done.isEmpty else { return nil }
        let uploaded = done.filter { $0.cloudUploadStatus == .uploaded }.count
        return Int((Double(uploaded) / Double(done.count) * 100).rounded())
    }

    private var latestEvent: Event? { app.events.first }

    var body: some View {
        ZStack {
            AtmosphericBackground()

            ScrollView {
                VStack(spacing: BoothifySpacing.md) {
                    greetingHeader
                        .padding(.bottom, BoothifySpacing.xs)

                    startCard

                    if createExpanded {
                        createZone
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    if let topErr = app.topLevelError {
                        Text(topErr)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    bentoRow

                    latestEventSection
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md + 2)
                .padding(.top, BoothifySpacing.sm)
                .padding(.bottom, BoothifySpacing.lg)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await app.loadRecentEvents() }
        }
        // The designed greeting header IS the screen's title.
        .toolbar(.hidden, for: .navigationBar)
        .task {
            CrashRestoreManager.clearActiveEvent()
            await app.loadRecentEvents()
        }
    }

    // MARK: - Greeting header

    private var greetingHeader: some View {
        HStack(spacing: BoothifySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Welcome back")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BoothifyTheme.textSecondary)
                Text(operatorName)
                    .font(.title.weight(.heavy))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BoothifyTheme.amber, BoothifyTheme.amber.opacity(0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: BoothifyTheme.amber.opacity(0.35), radius: 12)
                Text(String(operatorName.prefix(1)))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.black)
            }
            .accessibilityHidden(true)
        }
        .padding(.top, BoothifySpacing.sm)
    }

    // MARK: - Start card (bento hero)

    private var startCard: some View {
        Button {
            Haptics.tap(.light)
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
                createExpanded.toggle()
            }
            if createExpanded { nameFocused = true }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [BoothifyTheme.amber, BoothifyTheme.amber.opacity(0.75)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 50, height: 50)
                            .shadow(color: BoothifyTheme.amber.opacity(0.55), radius: 14)
                        Image(systemName: "rotate.3d.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.black)
                    }
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.14))
                            .frame(width: 36, height: 36)
                            .overlay(Circle().stroke(.white.opacity(0.20), lineWidth: 1))
                        Image(systemName: "chevron.right")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .rotationEffect(.degrees(createExpanded ? 90 : 0))
                    }
                }
                Spacer(minLength: BoothifySpacing.md)
                Text("Start a new session")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                Text("Spin up the booth for your next event")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 3)
            }
            .padding(BoothifySpacing.md + 4)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .leading)
            // Violet-tinted glass — the hero sits a shade warmer than the
            // quiet tiles below (composition per the bento reference).
            .background(
                LinearGradient(
                    colors: [BoothifyTheme.indigoGlow.opacity(0.42), BoothifyTheme.violet.opacity(0.14)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 26, style: .continuous)
            )
            .glassSurface(radius: 26)
            .glowAccent(intensity: createExpanded ? 0.2 : 0.42)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start a new session")
        .accessibilityHint(createExpanded ? "Collapses the event form" : "Opens the event form")
    }

    // MARK: - Create zone (expands under the hero)

    private var canStart: Bool {
        eventName.trimmingCharacters(in: .whitespaces).count >= 2 && !creating
    }

    private var createZone: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm + 4) {
            TextField(
                "",
                text: $eventName,
                prompt: Text("Name your event…")
                    .foregroundColor(BoothifyTheme.textMuted)
            )
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, BoothifySpacing.md)
            .frame(minHeight: 54)
            .glassSurface(radius: BoothifyRadius.card)
            .overlay(
                RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                    .stroke(BoothifyTheme.amber.opacity(nameFocused ? 0.55 : 0), lineWidth: 1.5)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: nameFocused)
            .focused($nameFocused)
            .submitLabel(.go)
            .onSubmit { startSession() }
            .textInputAutocapitalization(.words)
            .disabled(creating)

            // 1-tap templates: a chip names AND pre-configures the event.
            HStack(spacing: BoothifySpacing.xs + 2) {
                ForEach(EventTemplate.allCases) { template in
                    Booth360TemplateChip(label: template.label, selected: selectedTemplate == template) {
                        Haptics.tap(.light)
                        selectedTemplate = template
                        // Never overwrite a name the operator typed; only seed an
                        // empty field or replace a prior chip's seed.
                        let typed = eventName.trimmingCharacters(in: .whitespaces)
                        if typed.isEmpty || EventTemplate.allCases.contains(where: { $0.nameSeed == typed }) {
                            eventName = template.nameSeed
                        }
                        nameFocused = true
                    }
                    .disabled(creating)
                }
            }

            if let t = selectedTemplate {
                Text(templateHint(t))
                    .font(.caption2)
                    .foregroundStyle(BoothifyTheme.textTertiary)
                    .padding(.leading, 4)
            }

            Button {
                startSession()
            } label: {
                HStack(spacing: 8) {
                    if creating {
                        ProgressView().tint(.black)
                    }
                    Text(creating ? "Creating event…" : "Start session")
                    if !creating {
                        Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .buttonStyle(AmberCTAButtonStyle())
            .disabled(!canStart)
            .opacity(canStart || creating ? 1 : 0.55)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: canStart)

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
        .padding(.top, 2)
    }

    // MARK: - Bento row: booth tile + stat tiles

    private var bentoRow: some View {
        HStack(alignment: .top, spacing: BoothifySpacing.md - 3) {
            boothTile
            VStack(spacing: BoothifySpacing.md - 3) {
                statTile(
                    value: "\(spinsCaptured)",
                    unit: nil,
                    label: "spins captured"
                )
                statTile(
                    value: deliveredPercent.map { "\($0)" } ?? "—",
                    unit: deliveredPercent != nil ? "%" : nil,
                    label: "delivered"
                )
            }
        }
    }

    private var boothTile: some View {
        ZStack(alignment: .bottomLeading) {
            // Color.clear base — the photo fills via overlay so its intrinsic
            // width never steals layout space from the stat column.
            Color.clear
                .overlay(
                    Image("Mode_360")
                        .resizable()
                        .scaledToFill()
                )

            // Wash — keeps the label legible and ties the photo into the
            // violet atmosphere (gradient on imagery is permitted).
            LinearGradient(
                colors: [BoothifyTheme.indigoGlow.opacity(0.15), .clear, .black.opacity(0.72)],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(app.hasActiveRenders ? BoothifyTheme.amber : BoothifyTheme.success)
                        .frame(width: 7, height: 7)
                        .shadow(color: (app.hasActiveRenders ? BoothifyTheme.amber : BoothifyTheme.success).opacity(0.9), radius: 5)
                    Text("YOUR BOOTH")
                        .font(.caption2.weight(.bold))
                        .kerning(0.5)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 4)
                }
                Text(app.hasActiveRenders ? "Rendering in background" : "Ready · idle")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.75))
                    .shadow(color: .black.opacity(0.6), radius: 3)
            }
            .padding(BoothifySpacing.sm + 6)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 209)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.hasActiveRenders
                            ? "Your booth: a video is rendering in the background"
                            : "Your booth: ready")
    }

    private func statTile(value: String, unit: String?, label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value)
                    .font(.system(.title, design: .rounded).weight(.heavy).monospacedDigit())
                    .foregroundStyle(.white)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(BoothifyTheme.amber)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(BoothifyTheme.textTertiary)
        }
        .padding(.horizontal, BoothifySpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 98)
        .glassSurface(radius: 24)
    }

    // MARK: - Latest event

    @ViewBuilder
    private var latestEventSection: some View {
        if app.isLoadingEvents && app.events.isEmpty {
            ProgressView().tint(BoothifyTheme.amber)
                .frame(maxWidth: .infinity)
                .padding(.top, BoothifySpacing.sm)
        } else if let event = latestEvent {
            let spins = app.jobs(for: event.id).filter { $0.status == .completed }.count
            Button {
                Haptics.tap()
                app.push(.booth360EventHub(eventId: event.id))
            } label: {
                HStack(spacing: BoothifySpacing.md - 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [BoothifyTheme.amber.opacity(0.35), BoothifyTheme.amber.opacity(0.08)],
                                    center: .topLeading, startRadius: 0, endRadius: 70
                                )
                            )
                            .frame(width: 60, height: 60)
                            .overlay(
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(.white.opacity(0.14), lineWidth: 1)
                            )
                        Image(systemName: "rotate.3d")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("LATEST EVENT")
                            .font(.caption2.weight(.bold))
                            .kerning(1.0)
                            .foregroundStyle(BoothifyTheme.textMuted)
                        Text(event.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(event.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                            .font(.caption)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }

                    Spacer(minLength: BoothifySpacing.sm)

                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(spins)")
                            .font(.title3.weight(.heavy).monospacedDigit())
                            .foregroundStyle(BoothifyTheme.amber)
                        Text("SPINS")
                            .font(.caption2.weight(.semibold))
                            .kerning(0.5)
                            .foregroundStyle(BoothifyTheme.textMuted)
                    }
                }
                .padding(BoothifySpacing.md)
                .glassSurface(radius: 24)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the event hub")
        } else {
            // Quiet whisper — the hero above carries the screen.
            VStack(alignment: .leading, spacing: 3) {
                Text("No events yet")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textTertiary)
                Text("Your first event will appear here.")
                    .font(.caption2)
                    .foregroundStyle(BoothifyTheme.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, BoothifySpacing.xs)
        }
    }

    // MARK: - Actions

    private func templateHint(_ t: EventTemplate) -> String {
        switch t {
        case .wedding:   return "Sets up branding + photo consent. No survey."
        case .birthday:  return "Low-friction fun: no forms."
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
                // 1-tap template: pre-configure the new event's settings.
                if let template {
                    let configured = template.apply(to: app.settings(for: event.id), eventName: trimmed)
                    app.updateSettings(configured, for: event.id)
                }
                Haptics.notify(.success)
                creating = false
                eventName = ""
                selectedTemplate = nil
                createExpanded = false
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

// MARK: - Template chip (1-tap event presets, 360 accent)

private struct Booth360TemplateChip: View {
    let label: String
    var selected: Bool = false
    let action: () -> Void
    @State private var pressed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? .black : BoothifyTheme.amber)
                .padding(.horizontal, BoothifySpacing.sm + 2)
                .padding(.vertical, 7)
                .background(BoothifyTheme.amber.opacity(selected ? 1.0 : 0.14), in: Capsule())
                .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(selected ? 0 : 0.32), lineWidth: 1))
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

#Preview {
    NavigationStack {
        Booth360LandingView()
    }
    .environment(AppState())
}
