import SwiftUI

/// IM2: at-a-glance pipeline counters for an event. Mounts in EventHub /
/// Booth360EventHub. Pulls from `AppState.cloudStatus(for:)` (always
/// populated) and refreshes on appear + after major actions.
///
/// Tap-anywhere on the row triggers a refresh. Counters animate.
struct CloudStatusPanel: View {
    @Environment(AppState.self) private var app
    let eventId: UUID

    @State private var refreshing: Bool = false

    private var status: EventCloudStatus { app.cloudStatus(for: eventId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "icloud.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text("Cloud status")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.textSecondary)
                Spacer()
                Button {
                    Haptics.tap(.light)
                    Task {
                        refreshing = true
                        await app.refreshCloudStatus(for: eventId)
                        try? await Task.sleep(for: .milliseconds(250))
                        refreshing = false
                    }
                } label: {
                    Image(systemName: refreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .rotationEffect(refreshing ? .degrees(360) : .zero)
                        .animation(refreshing
                                   ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                   : .default,
                                   value: refreshing)
                }
                .accessibilityLabel("Refresh cloud status")
            }

            HStack(spacing: 8) {
                counter("In queue", count: status.queued, tint: BoothifyTheme.textTertiary, symbol: "clock")
                counter("Uploading", count: status.uploading, tint: BoothifyTheme.amber, symbol: "icloud.and.arrow.up.fill")
                counter("Done", count: status.done, tint: BoothifyTheme.emerald, symbol: "checkmark.seal.fill")
                counter("Sent", count: status.sent, tint: BoothifyTheme.violet, symbol: "paperplane.fill")
            }
        }
        .padding(14)
        .background(BoothifyTheme.surface1)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: eventId) {
            // Initial fetch — uses local snapshot first then races a backend call.
            await app.refreshCloudStatus(for: eventId)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cloud status: \(status.queued) queued, \(status.uploading) uploading, \(status.done) done, \(status.sent) sent")
    }

    @ViewBuilder
    private func counter(_ label: String, count: Int, tint: Color, symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .bold))
                Text("\(count)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .contentTransition(.numericText())
            }
            .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .kerning(0.4)
                .foregroundStyle(BoothifyTheme.textTertiary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tint.opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    CloudStatusPanel(eventId: UUID())
        .padding()
        .environment(AppState())
        .background(BoothifyTheme.bg)
}
