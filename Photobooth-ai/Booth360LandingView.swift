import SwiftUI

/// 360 AI Booth event launcher. Mirrors `PhotoboothLandingView` for parity but
/// routes into the dedicated 360 flow (recording → processing → result) on
/// create. Recent events list is the shared `app.events` list — operators see
/// all of their events regardless of which mode they were created in.
struct Booth360LandingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var eventName: String = ""
    @State private var creating: Bool = false
    @State private var createError: String? = nil
    @State private var selectedTemplate: EventTemplate? = nil
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            AtmosphericBackground()

            ScrollView {
                // Layout redesign: no mega-card. The screen is three breathing
                // zones — headline, a light create zone floating directly on
                // the atmosphere, and a quiet recents list. One dominant: the
                // glowing amber CTA.
                VStack(alignment: .leading, spacing: BoothifySpacing.xl) {
                    headerBlock

                    newSessionZone

                    if let topErr = app.topLevelError {
                        Text(topErr)
                            .font(.footnote)
                            .foregroundStyle(BoothifyTheme.error)
                    }

                    recentEventsSection
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, BoothifySpacing.md + 4)
                .padding(.top, BoothifySpacing.md)
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
        VStack(alignment: .leading, spacing: BoothifySpacing.sm + 4) {
            // Mode chip — a small floating capsule, not a full-width box.
            // The atmosphere stays visible around it.
            HStack(spacing: 6) {
                Circle()
                    .fill(BoothifyTheme.amber)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text("360 mode")
                    .font(.caption.weight(.semibold))
                Text("BETA")
                    .font(.caption2.weight(.bold))
                    .kerning(0.6)
                    .opacity(0.75)
            }
            .foregroundStyle(BoothifyTheme.amber)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(BoothifyTheme.amber.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(BoothifyTheme.amber.opacity(0.28), lineWidth: 1))

            Text("Start a new\n360 session")
                .font(BoothifyType.hero)
                .foregroundStyle(.white)
                .lineSpacing(1)

            Text("Capture rotating 360° clips and let AI turn them into cinematic shareable videos.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .lineSpacing(3)
                .frame(maxWidth: 460, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - New session zone
    //
    // Layout redesign: no enclosing mega-card. The input is its own light
    // glass field, chips float directly on the atmosphere, and the CTA is
    // the screen's single glowing dominant.

    private var canStart: Bool {
        eventName.trimmingCharacters(in: .whitespaces).count >= 2 && !creating
    }

    private var newSessionZone: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.md) {
            TextField(
                "",
                text: $eventName,
                prompt: Text("Name your event…")
                    .foregroundColor(BoothifyTheme.textMuted)
            )
            .font(.body)
            .foregroundStyle(.white)
            .padding(.horizontal, BoothifySpacing.md)
            .frame(minHeight: 56)
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

            // 1-tap templates (ported from the photo landing per blueprint 4.G):
            // a chip names AND pre-configures the event on create.
            VStack(alignment: .leading, spacing: BoothifySpacing.xs + 2) {
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
            .glowAccent(intensity: canStart ? 0.55 : 0.15)
            .disabled(!canStart)
            .opacity(canStart || creating ? 1 : 0.55)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: canStart)
            .padding(.top, BoothifySpacing.xs)

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
    }

    // MARK: - Recent events

    @ViewBuilder
    private var recentEventsSection: some View {
        if app.isLoadingEvents && app.events.isEmpty {
            ProgressView().tint(BoothifyTheme.amber)
                .frame(maxWidth: .infinity)
                .padding(.top, BoothifySpacing.md)
        } else if app.events.isEmpty {
            // Quiet background whisper — never a competitor to the CTA.
            Booth360EmptyState()
        } else {
            VStack(alignment: .leading, spacing: BoothifySpacing.sm + 2) {
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

// MARK: - Template chip (ported from the photo landing, 360 accent)

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

// MARK: - Row & empty state

struct Booth360EventRow: View {
    let event: Event
    let jobs: [Booth360Job]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Light, airy row — small thumb, slim padding, glass stays thin
            // so the list reads as floating entries, not stacked bricks.
            HStack(spacing: BoothifySpacing.sm + 2) {
                thumbnail
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.micro + 2, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.name)
                        .font(.subheadline.weight(.semibold))
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
            .padding(.horizontal, BoothifySpacing.sm + 4)
            .padding(.vertical, BoothifySpacing.sm + 2)
            .glassSurface(radius: BoothifyRadius.card)
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

/// Layout redesign: the landing empty state is a whisper, not a competitor —
/// the CTA above is the screen's story. Two quiet lines, no icon box.
struct Booth360EmptyState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("No 360 sessions yet")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BoothifyTheme.textTertiary)
            Text("Your first event will appear here.")
                .font(.caption2)
                .foregroundStyle(BoothifyTheme.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, BoothifySpacing.sm)
    }
}

#Preview {
    NavigationStack {
        Booth360LandingView()
    }
    .environment(AppState())
}
