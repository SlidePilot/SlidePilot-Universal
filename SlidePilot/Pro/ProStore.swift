import SlidePilotCore
import Foundation
import Observation

#if SLIDEPILOT_FREE_DOWNLOAD

/// The free Mac download (ADR 0011, ADR 0020): no limits and no StoreKit code. Same API as
/// the App Store store below, so the rest of the app needs no `#if`.
@MainActor
@Observable
final class ProStore {
    /// Always unlimited in this build.
    let status: ProStatus = .unlimited
    /// No in-app purchase in this build.
    let productID: String? = nil

    func start() {}
    func refreshStatus() async {}
    func purchase() async throws -> ProPurchaseOutcome { throw ProStoreError.productUnavailable }
    func restore() async throws {}
}

#else

import StoreKit

/// The Pro status of this App Store installation and the purchase of SlidePilot Pro (PRO-02,
/// ADR 0020). The app owns one instance and passes it through the environment.
///
/// The status starts `unknown` and follows StoreKit's current entitlements: at `start()`,
/// after every transaction update (purchases on other devices, Family Sharing, refunds and
/// revocations, Ask to Buy approvals), after `purchase()` and after `restore()`.
@MainActor
@Observable
final class ProStore {
    private(set) var status: ProStatus = .unknown
    /// The product ID from the Info.plist (`SLIDEPILOT_PRO_PRODUCT_ID`); `nil` if the build has
    /// none, then Pro cannot be bought and the status stays locked.
    let productID: String?

    @ObservationIgnored private var product: Product?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGeneration = 0

    init(bundle: Bundle = .main) {
        productID = ProProductID.from(infoPlistValue: bundle.object(forInfoDictionaryKey: ProProductID.infoPlistKey))
    }

    isolated deinit {
        updatesTask?.cancel()
        refreshTask?.cancel()
    }

    /// Starts listening for transactions and checks the entitlements. Call once at launch, so
    /// no transaction (e.g. an approved Ask to Buy) is missed. Calling it again does nothing.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await handle(update)
            }
        }
        refreshTask = Task { [weak self] in
            // Transactions that an earlier launch did not get to finish.
            for await unfinished in Transaction.unfinished {
                if case .verified(let transaction) = unfinished {
                    await transaction.finish()
                }
            }
            await self?.refreshStatus()
        }
    }

    /// Derives the status from StoreKit's current entitlements again. `currentEntitlements`
    /// leaves out refunded and revoked purchases; the Core rule checks the revocation as well.
    func refreshStatus() async {
        // Overlapping checks (launch, update, purchase) finish in any order; only the one that
        // started last may set the status, so an older answer never undoes a newer one.
        refreshGeneration += 1
        let generation = refreshGeneration
        var entitlements: [ProEntitlement] = []
        for await result in Transaction.currentEntitlements {
            // An unverified transaction never unlocks Pro.
            guard case .verified(let transaction) = result else { continue }
            entitlements.append(ProEntitlement(transaction))
        }
        guard generation == refreshGeneration else { return }
        status = ProStatus(entitlements: entitlements, productID: productID)
    }

    /// Buys SlidePilot Pro with the system's purchase sheet.
    ///
    /// - Returns: `.purchased` once Pro is unlocked, `.pending` while it waits for approval
    ///   (Ask to Buy, Strong Customer Authentication; the result arrives later as a transaction
    ///   update), `.cancelled` if the user cancelled.
    /// - Throws: `ProStoreError.productUnavailable` if the product cannot be loaded,
    ///   `ProStoreError.unverified` for a transaction that failed verification, or a StoreKit
    ///   error.
    func purchase() async throws -> ProPurchaseOutcome {
        let product = try await loadProduct()
        switch try await product.purchase() {
        case .success(let result):
            guard case .verified(let transaction) = result else { throw ProStoreError.unverified }
            await transaction.finish()
            await refreshStatus()
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Restore Purchases: syncs the transactions with the App Store (may ask the user to sign
    /// in) and checks the entitlements again. Entitlements usually arrive by themselves; this is
    /// for the user who asks for it.
    func restore() async throws {
        try await AppStore.sync()
        await refreshStatus()
    }

    private func loadProduct() async throws -> Product {
        if let product { return product }
        guard let productID, let loaded = try await Product.products(for: [productID]).first else {
            throw ProStoreError.productUnavailable
        }
        product = loaded
        return loaded
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        // Unverified updates are not finished, so StoreKit offers them again.
        if case .verified(let transaction) = update {
            await transaction.finish()
        }
        await refreshStatus()
    }
}

private extension ProEntitlement {
    init(_ transaction: Transaction) {
        self.init(
            productID: transaction.productID,
            ownership: transaction.ownershipType == .familyShared ? .familyShared : .purchased,
            revocationDate: transaction.revocationDate
        )
    }
}

#endif

/// How `ProStore.purchase()` ended without an error.
enum ProPurchaseOutcome: Sendable, Equatable {
    case purchased
    case pending
    case cancelled
}

enum ProStoreError: Error, Equatable {
    /// The product could not be loaded (no product ID, no connection, or not in the store).
    case productUnavailable
    /// The App Store's signature of the transaction did not verify.
    case unverified
}
