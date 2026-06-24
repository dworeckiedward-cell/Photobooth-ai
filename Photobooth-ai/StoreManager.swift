import Foundation
import StoreKit

/// Subscription tiers. Order matters: `rank` gates feature access (higher unlocks
/// everything below it). Pricing mirrors the category benchmark (LumaBooth ~$18–20/mo).
enum SubscriptionTier: String, CaseIterable, Sendable {
    case free, starter, pro, business

    var rank: Int {
        switch self {
        case .free:     return 0
        case .starter:  return 1
        case .pro:      return 2
        case .business: return 3
        }
    }

    var displayName: String {
        switch self {
        case .free:     return "Free"
        case .starter:  return "Starter"
        case .pro:      return "Pro"
        case .business: return "Business"
        }
    }

    /// App Store Connect product identifier for this tier's monthly subscription.
    /// TODO(human): create these auto-renewable subscription products in App Store
    /// Connect (one group "Boothify") with a 14-day intro free trial, and add a
    /// Boothify.storekit configuration to the scheme for local sandbox testing.
    var productID: String? {
        switch self {
        case .free:     return nil
        case .starter:  return "com.servify.boothify.starter.monthly"
        case .pro:      return "com.servify.boothify.pro.monthly"
        case .business: return "com.servify.boothify.business.monthly"
        }
    }

    static func tier(for productID: String) -> SubscriptionTier {
        allCases.first { $0.productID == productID } ?? .free
    }
}

/// Premium capabilities gated by tier. Single source of truth so UI and flows
/// agree on what each plan unlocks.
enum PremiumFeature {
    case aiPortraits, booth360, printing, whiteLabel, multiDevice, kioskFleet

    var minimumTier: SubscriptionTier {
        switch self {
        case .aiPortraits, .printing: return .pro
        case .booth360, .whiteLabel:  return .pro
        case .multiDevice:            return .pro
        case .kioskFleet:             return .business
        }
    }
}

/// StoreKit 2 wrapper. Loads products, runs purchases, listens for transaction
/// updates, and exposes the current entitlement tier. No third-party dependency.
@Observable
@MainActor
final class StoreManager {
    /// Loaded products, ordered by tier rank.
    private(set) var products: [Product] = []
    /// The highest tier the user currently has an active entitlement for.
    private(set) var currentTier: SubscriptionTier = .free
    private(set) var isLoading = false
    private(set) var lastError: String?

    init() {
        // Start listening for transactions (renewals, refunds, purchases made on
        // other devices) immediately, before any UI asks. StoreManager lives for
        // the whole app lifetime (a single @State in RootView), so the listener
        // is never orphaned — no explicit cancellation needed.
        Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(transactionResult: update)
            }
        }
    }

    /// Does the current plan unlock `feature`?
    func canUse(_ feature: PremiumFeature) -> Bool {
        currentTier.rank >= feature.minimumTier.rank
    }

    /// Load products from the App Store and refresh entitlements.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        let ids = SubscriptionTier.allCases.compactMap(\.productID)
        do {
            let loaded = try await Product.products(for: ids)
            products = loaded.sorted {
                SubscriptionTier.tier(for: $0.id).rank < SubscriptionTier.tier(for: $1.id).rank
            }
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    /// Recompute `currentTier` from the active entitlements (verified only).
    func refreshEntitlements() async {
        var best: SubscriptionTier = .free
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let transaction) = entitlement else { continue }
            if transaction.revocationDate != nil { continue }
            if let exp = transaction.expirationDate, exp < Date() { continue }
            let tier = SubscriptionTier.tier(for: transaction.productID)
            if tier.rank > best.rank { best = tier }
        }
        currentTier = best
    }

    /// Purchase a product. Returns true on a verified success.
    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                    return true
                }
                lastError = "Purchase could not be verified."
                return false
            case .userCancelled, .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Restore purchases (App Store sync). Required by App Review for subscriptions.
    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }

    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        await transaction.finish()
        await refreshEntitlements()
    }
}
