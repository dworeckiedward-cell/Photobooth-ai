import SwiftUI

/// IM2: at-a-glance pipeline counters for an event. Mounts in EventHub /
/// Booth360EventHub. Pulls from `AppState.cloudStatus(for:)` (always
/// populated) and refreshes on appear + after major actions.
///
/// Tap-anywhere on the row triggers a refresh. Counters animate.
struct CloudStatusPanel: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let eventId: UUID

    @State private var refreshing: Bool = false
    @State private var initialLoading: Bool = true

    private var status: EventCloudStatus { app.cloudStatus(for: eventId) }
    private var isEmpty: Bool { status.queued == 0 && status.uploading == 0 && status.done == 0 && status.sent == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: BoothifySpacing.sm) {
            // Header
            HStack(spacing: BoothifySpacing.xs) {
                Image(systemName: "icloud.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                Text("Cloud status")
                    .font(BoothifyType.captionEmphasis)
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
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(refreshing ? BoothifyTheme.violet : BoothifyTheme.textTertiary)
                        .rotationEffect(refreshing ? .degrees(360) : .zero)
                        .animation(
                            reduceMotion ? nil : (refreshing
                                ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                : .default),
                            value: refreshing
                        )
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh cloud status")
            }

            Divider()
                .overlay(BoothifyTheme.surfaceLine)

            // Content
            if initialLoading {
                // Loading skeleton
                HStack(spacing: BoothifySpacing.sm) {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: BoothifySpacing.xs) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(BoothifyTheme.surface2)
                                .frame(height: 22)
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(BoothifyTheme.surface2)
                                .frame(height: 10)
                                .padding(.horizontal, BoothifySpacing.sm)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, BoothifySpacing.sm)
                        .background(BoothifyTheme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                    }
                }
                .redacted(reason: .placeholder)
            } else {
                // Counter grid
                HStack(spacing: BoothifySpacing.xs) {
                    counter("Queued", count: status.queued, tint: BoothifyTheme.textTertiary, symbol: "clock.fill")
                    counter("Uploading", count: status.uploading, tint: BoothifyTheme.violet, symbol: "icloud.and.arrow.up.fill")
                    counter("Done", count: status.done, tint: BoothifyTheme.emerald, symbol: "checkmark.seal.fill")
                    counter("Sent", count: status.sent, tint: BoothifyTheme.emerald, symbol: "paperplane.fill")
                }

                // Uploading progress bar
                if status.uploading > 0 {
                    let total = status.queued + status.uploading + status.done + status.sent
                    let progress = total > 0 ? Double(status.done + status.sent) / Double(total) : 0

                    VStack(alignment: .leading, spacing: BoothifySpacing.xs) {
                        HStack {
                            Text("Upload progress")
                                .font(BoothifyType.caption)
                                .foregroundStyle(BoothifyTheme.textTertiary)
                            Spacer()
                            Text("\(Int(progress * 100))%")
                                .font(BoothifyType.captionEmphasis)
                                .foregroundStyle(BoothifyTheme.textSecondary)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(BoothifyTheme.surface2)
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(BoothifyTheme.violet)
                                    .frame(width: geo.size.width * progress, height: 6)
                                    .animation(.spring(response: 0.5), value: progress)
                            }
                        }
                        .frame(height: 6)
                    }
                    .padding(.top, BoothifySpacing.xs)
                }

                // Offline photo queue indicator
                let offlineCount = PhotoUploadQueue.shared.pendingCount
                if offlineCount > 0 {
                    HStack(spacing: BoothifySpacing.xs) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BoothifyTheme.violet)
                        Text("\(offlineCount) photo\(offlineCount == 1 ? "" : "s") pending upload")
                            .font(BoothifyType.caption)
                            .foregroundStyle(BoothifyTheme.textSecondary)
                        Spacer()
                        Text("Queued offline")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(BoothifyTheme.textTertiary)
                    }
                    .padding(BoothifySpacing.sm)
                    .background(BoothifyTheme.violet.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                            .stroke(BoothifyTheme.violet.opacity(0.20), lineWidth: 0.5)
                    )
                    .padding(.top, BoothifySpacing.xs)
                }

                // Empty hint
                if isEmpty && offlineCount == 0 {
                    Text("No activity yet — start capturing to see counters update.")
                        .font(BoothifyType.caption)
                        .foregroundStyle(BoothifyTheme.textMuted)
                        .padding(.top, BoothifySpacing.xs)
                }
            }
        }
        .padding(BoothifySpacing.md)
        .background(BoothifyTheme.surface1)
        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.card, style: .continuous)
                .stroke(BoothifyTheme.surfaceLine, lineWidth: 1)
        )
        .task(id: eventId) {
            defer { initialLoading = false }
            await app.refreshCloudStatus(for: eventId)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cloud status: \(status.queued) queued, \(status.uploading) uploading, \(status.done) done, \(status.sent) sent")
    }

    @ViewBuilder
    private func counter(_ label: String, count: Int, tint: Color, symbol: String) -> some View {
        VStack(spacing: BoothifySpacing.xs) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(count > 0 ? tint : BoothifyTheme.textMuted)

            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(count > 0 ? tint : BoothifyTheme.textMuted)
                .contentTransition(.numericText())

            Text(label)
                .font(.caption2.weight(.semibold))
                .kerning(0.4)
                .foregroundStyle(BoothifyTheme.textTertiary)
                .textCase(.uppercase)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, BoothifySpacing.sm)
        .background(count > 0 ? tint.opacity(0.08) : BoothifyTheme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: BoothifyRadius.input, style: .continuous)
                .stroke(count > 0 ? tint.opacity(0.20) : BoothifyTheme.surfaceLine, lineWidth: 0.5)
        )
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: count)
    }
}

#Preview {
    CloudStatusPanel(eventId: UUID())
        .padding()
        .environment(AppState())
        .background(BoothifyTheme.bg)
}
