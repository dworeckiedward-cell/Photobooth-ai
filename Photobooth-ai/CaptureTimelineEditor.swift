import SwiftUI

/// M6: operator-facing editor for the per-event capture timeline. Operates on
/// a single active `CaptureTemplate` (creates a copy of the default preset
/// the first time it's opened so the operator has something to tweak).
///
/// Segments support: duration (s), speed (×), reverse toggle. Live total
/// readout (raw vs rendered). Add / remove segments. Quick-load default
/// preset to reset.
struct CaptureTimelineEditor: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var template: CaptureTemplate = .defaultProduction
    @State private var hydrated: Bool = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Segments", value: "\(template.segments.count)")
                LabeledContent("Raw needed", value: String(format: "%.1fs", template.rawDuration))
                LabeledContent("Rendered length", value: String(format: "%.1fs", template.renderedDuration))
            } header: {
                Text("Total")
            } footer: {
                Text("Raw is footage the camera must capture. Rendered is the length of the final montage after speed adjustment.")
                    .font(.caption2)
            }

            Section {
                ForEach($template.segments) { $segment in
                    SegmentEditor(segment: $segment)
                }
                .onDelete { offsets in
                    template.segments.remove(atOffsets: offsets)
                    persist()
                }
                .onMove { from, to in
                    template.segments.move(fromOffsets: from, toOffset: to)
                    persist()
                }
                Button {
                    template.segments.append(
                        CaptureSegment(duration: 2.0, speed: 1.0, reverse: false)
                    )
                    persist()
                    Haptics.tap()
                } label: {
                    Label("Add segment", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Segments")
            }

            Section {
                Button {
                    template = .defaultProduction
                    template.id = UUID()
                    persist()
                    Haptics.notify(.success)
                } label: {
                    Label("Load default preset", systemImage: "arrow.counterclockwise")
                }

                // Sync recordingDurationSeconds with the raw needed by the
                // template so the recording screen captures enough footage.
                Button {
                    var settings = app.settings(for: eventId)
                    settings.ai360.recordingDurationSeconds = max(2.0, template.rawDuration)
                    app.updateSettings(settings, for: eventId)
                    Haptics.notify(.success)
                } label: {
                    Label("Match recording duration to template", systemImage: "stopwatch")
                }
            }
        }
        .navigationTitle("Capture Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(BoothifyTheme.bg.ignoresSafeArea())
        .toolbar {
            EditButton()
        }
        .onAppear { hydrateIfNeeded() }
        .onChange(of: template) { _, _ in persist() }
    }

    /// First-open path. If the operator hasn't built a template yet, drop in
    /// the default preset + activate it.
    private func hydrateIfNeeded() {
        guard !hydrated else { return }
        hydrated = true
        var settings = app.settings(for: eventId)

        if let activeId = settings.ai360.activeTemplateId,
           let active = settings.ai360.templates.first(where: { $0.id == activeId }) {
            template = active
            return
        }
        var fresh = CaptureTemplate.defaultProduction
        fresh.id = UUID()
        settings.ai360.templates = [fresh]
        settings.ai360.activeTemplateId = fresh.id
        app.updateSettings(settings, for: eventId)
        template = fresh
    }

    private func persist() {
        var settings = app.settings(for: eventId)
        // Upsert template by id.
        if let idx = settings.ai360.templates.firstIndex(where: { $0.id == template.id }) {
            settings.ai360.templates[idx] = template
        } else {
            settings.ai360.templates.append(template)
        }
        settings.ai360.activeTemplateId = template.id
        app.updateSettings(settings, for: eventId)
    }
}

private struct SegmentEditor: View {
    @Binding var segment: CaptureSegment

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: segment.reverse ? "arrow.uturn.left.circle.fill" : "play.circle.fill")
                    .foregroundStyle(segment.reverse ? BoothifyTheme.violet : BoothifyTheme.violet)
                Text(String(format: "%.1fs at %.2f×", segment.duration, segment.speed))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Toggle("Reverse", isOn: $segment.reverse)
                    .labelsHidden()
                    .tint(BoothifyTheme.violet)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Duration")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                    Spacer()
                    Text(String(format: "%.1fs", segment.duration))
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                }
                Slider(value: $segment.duration, in: 0.5...10.0, step: 0.1)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Speed")
                        .font(.caption)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                    Spacer()
                    Text(String(format: "%.2f×", segment.speed))
                        .font(.caption.monospaced())
                        .foregroundStyle(.white)
                }
                Slider(value: $segment.speed, in: 0.25...4.0, step: 0.05)
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        CaptureTimelineEditor(eventId: UUID())
    }
    .environment(AppState())
}
