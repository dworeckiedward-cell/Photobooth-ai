import SwiftUI
import StoreKit

/// Subscription paywall. Lists the loaded StoreKit products by tier, runs the
/// purchase, and supports Restore (required by App Review). Shows a graceful
/// empty state until the App Store Connect products exist (TODO(human)).
struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var working = false

    var body: some View {
        NavigationStack {
            ZStack {
                BoothifyTheme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: BoothifySpacing.lg) {
                        header

                        if store.products.isEmpty {
                            emptyState
                        } else {
                            ForEach(store.products, id: \.id) { product in
                                planCard(product)
                            }
                        }

                        Button {
                            Task { working = true; await store.restore(); working = false }
                        } label: {
                            Text("Restore purchases")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(BoothifyTheme.violet)
                        }
                        .padding(.top, BoothifySpacing.sm)

                        Text("Subscriptions renew automatically until cancelled. Manage or cancel anytime in the App Store. Includes a 14-day free trial.")
                            .font(.caption2)
                            .foregroundStyle(BoothifyTheme.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, BoothifySpacing.lg)
                    }
                    .frame(maxWidth: 560)
                    .padding(BoothifySpacing.md)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Boothify Plans")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(BoothifyTheme.violet)
                        .font(.body.weight(.semibold))
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: BoothifySpacing.xs) {
            Text("Go Pro")
                .font(BoothifyType.displayMedium)
                .foregroundStyle(.white)
            Text("Unlock AI portraits, 360, printing and white-label branding.")
                .font(.subheadline)
                .foregroundStyle(BoothifyTheme.textSecondary)
                .multilineTextAlignment(.center)
            if store.currentTier != .free {
                Text("Current plan: \(store.currentTier.displayName)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BoothifyTheme.violet)
                    .padding(.top, 2)
            }
        }
        .padding(.top, BoothifySpacing.md)
    }

    private func planCard(_ product: Product) -> some View {
        let tier = SubscriptionTier.tier(for: product.id)
        let isCurrent = store.currentTier == tier
        return Button {
            Task { working = true; _ = await store.purchase(product); working = false }
        } label: {
            HStack(spacing: BoothifySpacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tier.displayName)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text(product.description)
                        .font(.footnote)
                        .foregroundStyle(BoothifyTheme.textTertiary)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(product.displayPrice)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(isCurrent ? "Current" : "/ month")
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? BoothifyTheme.emerald : BoothifyTheme.textMuted)
                }
            }
            .padding(BoothifySpacing.lg)
            .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isCurrent ? BoothifyTheme.violet.opacity(0.6) : BoothifyTheme.surfaceLine, lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(working || isCurrent)
        .opacity(isCurrent ? 0.7 : 1)
    }

    private var emptyState: some View {
        VStack(spacing: BoothifySpacing.sm) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(BoothifyTheme.violet)
            Text("Plans are being set up")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Subscription plans will appear here once they're live in the App Store.")
                .font(.footnote)
                .foregroundStyle(BoothifyTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(BoothifySpacing.xl)
        .background(BoothifyTheme.surface1, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
