import SwiftUI
import StoreKit

/// Subscription paywall. Lists the loaded StoreKit products by tier, runs the
/// purchase, and supports Restore (required by App Review). Shows a graceful
/// empty state until the App Store Connect products exist (TODO(human)).
struct PaywallView: View {
    @Environment(StoreManager.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var working = false

    private var privacyURL: URL { BoothifyAPI.shared.baseURL.appending(path: "privacy") }
    private var termsURL: URL { BoothifyAPI.shared.baseURL.appending(path: "terms") }

    var body: some View {
        NavigationStack {
            ZStack {
                AtmosphericBackground()

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

                        // Required by App Review: reachable Privacy Policy + Terms (EULA).
                        HStack(spacing: BoothifySpacing.sm) {
                            Button("Privacy Policy") { openURL(privacyURL) }
                            Text("·").foregroundStyle(BoothifyTheme.textMuted)
                            Button("Terms of Use") { openURL(termsURL) }
                        }
                        .font(.caption2.weight(.medium))
                        .tint(BoothifyTheme.textSecondary)
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
                    Text(isCurrent ? "Current" : periodLabel(product))
                        .font(.caption2)
                        .foregroundStyle(isCurrent ? BoothifyTheme.emerald : BoothifyTheme.textMuted)
                }
            }
            .padding(BoothifySpacing.lg)
            .glassSurface(radius: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(isCurrent ? BoothifyTheme.violet.opacity(0.6) : BoothifyTheme.surfaceLine, lineWidth: isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(working || isCurrent)
        .opacity(isCurrent ? 0.7 : 1)
    }

    /// Derive the billing period from the product so an annual plan never shows
    /// "/ month" (accurate pricing is an App Review requirement).
    private func periodLabel(_ product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else { return "" }
        let unit: String
        switch period.unit {
        case .day:   unit = "day"
        case .week:  unit = "week"
        case .month: unit = "month"
        case .year:  unit = "year"
        @unknown default: unit = "period"
        }
        return period.value == 1 ? "/ \(unit)" : "/ \(period.value) \(unit)s"
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
        .glassSurface(radius: 20)
    }
}
