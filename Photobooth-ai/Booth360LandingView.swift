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
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var nameFocused: Bool

    /// 0…1 progress of the scroll-linked background effect (settles ~260pt).
    private var scrollProgress: CGFloat { min(max(scrollOffset, 0) / 260, 1) }

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

    /// Most recent event that is NOT the live one — the current event has
    /// its own banner above.
    private var latestEvent: Event? {
        app.events.first(where: { $0.id != app.currentEventId })
    }

    var body: some View {
        ZStack {
            homeBackground

            // Bottom-anchored bento: the greeting holds the top edge, the tile
            // cluster sinks to the bottom (one nav-height of air above the
            // floating pill), and the ambient clip breathes in between.
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: BoothifySpacing.md) {
                        greetingHeader
                            .padding(.bottom, BoothifySpacing.xs)
                            .entrance(0)

                        Spacer(minLength: BoothifySpacing.xl)

                        startCard
                            .entrance(1)

                        if let topErr = app.topLevelError {
                            Text(topErr)
                                .font(.footnote)
                                .foregroundStyle(BoothifyTheme.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let current = currentEvent {
                            currentEventBanner(current)
                                .entrance(2)
                        }

                        bentoRow
                            .entrance(3)

                        latestEventSection
                            .entrance(4)
                    }
                    .frame(maxWidth: 620)
                    .padding(.horizontal, BoothifySpacing.md + 2)
                    .padding(.top, BoothifySpacing.sm)
                    // RootView already reserves the nav clearance; this adds
                    // the extra ~nav-height of deliberate air above the pill.
                    .padding(.bottom, BoothifySpacing.md)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                    // Scroll tracking for the parallax background.
                    .background(
                        GeometryReader { inner in
                            Color.clear.preference(
                                key: HomeScrollOffsetKey.self,
                                value: -inner.frame(in: .named("homeScroll")).minY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "homeScroll")
                .onPreferenceChange(HomeScrollOffsetKey.self) { scrollOffset = $0 }
                .refreshable { await app.loadRecentEvents() }
            }
        }
        // The designed greeting header IS the screen's title.
        .toolbar(.hidden, for: .navigationBar)
        // New-event popup: dimmed stage + fading glass card, keyboard-first.
        .overlay { createPopup }
        .task {
            CrashRestoreManager.clearActiveEvent()
            await app.loadRecentEvents()
        }
    }

    // MARK: - Current event

    private var currentEvent: Event? {
        guard let id = app.currentEventId else { return nil }
        return app.events.first(where: { $0.id == id })
    }

    /// "Continue your current event" — the first banner when a gig is live.
    private func currentEventBanner(_ event: Event) -> some View {
        Button {
            Haptics.tap(.medium)
            app.push(.booth360EventHub(eventId: event.id))
        } label: {
            HStack(spacing: BoothifySpacing.md - 2) {
                ZStack {
                    Circle()
                        .fill(BoothifyTheme.violet.opacity(0.22))
                        .frame(width: 44, height: 44)
                    Circle()
                        .fill(BoothifyTheme.violet)
                        .frame(width: 10, height: 10)
                        .shadow(color: BoothifyTheme.violet.opacity(0.9), radius: 6)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CURRENT EVENT")
                        .font(.caption2.weight(.bold))
                        .kerning(1.0)
                        .lineLimit(1)
                        .foregroundStyle(BoothifyTheme.violet)
                    Text(event.name)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }

                Spacer(minLength: BoothifySpacing.sm)

                HStack(spacing: 5) {
                    Text("Continue")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(.white)
            }
            .padding(BoothifySpacing.md)
            .background(
                LinearGradient(
                    colors: [BoothifyTheme.violet.opacity(0.30), BoothifyTheme.violet.opacity(0.10)],
                    startPoint: .leading, endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .glassSurface(radius: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Continue your current event, \(event.name)")
        .accessibilityHint("Opens the live event panel")
    }

    // MARK: - Create popup (dim + fade)

    @ViewBuilder
    private var createPopup: some View {
        ZStack(alignment: .top) {
            if createExpanded {
                // Dimmer — tap outside dismisses.
                Color.black.opacity(0.62)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { closeCreate() }
                    .accessibilityLabel("Dismiss")

                VStack(alignment: .leading, spacing: BoothifySpacing.md) {
                    HStack {
                        Text("New event")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button {
                            closeCreate()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Close")
                    }
                    createZone
                }
                .padding(BoothifySpacing.md + 4)
                .background(BoothifyTheme.bgElevated, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .glassSurface(radius: 28)
                .frame(maxWidth: 560)
                .padding(.horizontal, BoothifySpacing.md + 2)
                // Upper third — the keyboard never covers the form.
                .padding(.top, BoothifySpacing.xxl + BoothifySpacing.lg)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: createExpanded)
    }

    private func closeCreate() {
        Haptics.tap(.light)
        nameFocused = false
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            createExpanded = false
        }
    }

    // MARK: - Home background (the ambient booth clip, full-bleed)

    /// The booth clip replaces the black stage on Home only. A scrim keeps
    /// the greeting and glass tiles legible on top of the moving footage.
    /// Reduce Motion / missing asset → the shared black atmosphere.
    private var homeBackground: some View {
        ZStack {
            BoothifyTheme.bgDeep.ignoresSafeArea()

            if !reduceMotion,
               let clip = Bundle.main.url(forResource: "BoothAmbient", withExtension: "mp4") {
                // Scroll-linked parallax: the footage rides up with the
                // content while shrinking and dimming, so scrolling feels
                // like the stage recedes behind the tiles.
                AmbientVideoView(url: clip)
                    .ignoresSafeArea()
                    .scaleEffect(1 - 0.10 * scrollProgress)
                    .offset(y: -scrollOffset * 0.30)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.62), location: 0),
                        .init(color: .black.opacity(0.38), location: 0.4),
                        .init(color: .black.opacity(0.86), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea()
                Color.black.opacity(0.45 * scrollProgress)
                    .ignoresSafeArea()
            } else {
                AtmosphericBackground()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
                            colors: [BoothifyTheme.violet, BoothifyTheme.violet.opacity(0.65)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: BoothifyTheme.violet.opacity(0.35), radius: 12)
                Text(String(operatorName.prefix(1)))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
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
                                    colors: [BoothifyTheme.violet, BoothifyTheme.violet.opacity(0.75)],
                                    startPoint: .top, endPoint: .bottom
                                )
                            )
                            .frame(width: 50, height: 50)
                            .shadow(color: BoothifyTheme.violet.opacity(0.55), radius: 14)
                        Image(systemName: "rotate.3d.fill")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
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
            // Fixed height — the card must stay rigid inside the
            // bottom-anchored layout (a minHeight + inner Spacer would soak
            // up the flexible space meant for the atmosphere gap).
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 132)
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
                    .stroke(BoothifyTheme.violet.opacity(nameFocused ? 0.55 : 0), lineWidth: 1.5)
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
                        ProgressView().tint(.white)
                    }
                    Text(creating ? "Creating event…" : "Start session")
                    if !creating {
                        Image(systemName: "arrow.right").font(.subheadline.weight(.semibold))
                    }
                }
            }
            .buttonStyle(AccentCTAButtonStyle())
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

    // MARK: - Bento row: stat tiles (the booth clip lives in the background)

    private var bentoRow: some View {
        HStack(alignment: .top, spacing: BoothifySpacing.md - 3) {
            statTile(
                value: "\(spinsCaptured)",
                unit: nil,
                label: "spins captured"
            )
            statTile(
                value: deliveredPercent.map { "\($0)" } ?? "\u{2014}",
                unit: deliveredPercent != nil ? "%" : nil,
                label: "delivered"
            )
        }
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
                        .foregroundStyle(BoothifyTheme.violet)
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
            ProgressView().tint(BoothifyTheme.violet)
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
                                    colors: [BoothifyTheme.violet.opacity(0.35), BoothifyTheme.violet.opacity(0.08)],
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
                            .foregroundStyle(BoothifyTheme.violet)
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
                // The freshly created event becomes the live one.
                app.currentEventId = event.id
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

// MARK: - Scroll offset preference

private struct HomeScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

#Preview {
    NavigationStack {
        Booth360LandingView()
    }
    .environment(AppState())
}
