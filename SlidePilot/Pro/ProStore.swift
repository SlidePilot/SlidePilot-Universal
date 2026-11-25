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
    @ObservationIgnored private var latestRead: Task<[ProEntitlement], Never>?

    #if DEBUG
    /// Debug builds only: a status fixed without StoreKit, for the simulator (which never
    /// answers StoreKit outside Xcode) and the Mac snapshots, so the hint, the offer and
    /// Settings can be checked there. Set at launch with `-SlidePilotProStatus locked` (or
    /// `unlocked`).
    @ObservationIgnored private let fixedStatus: ProStatus?

    init(bundle: Bundle = .main, fixedStatus: ProStatus? = ProStore.launchArgumentStatus) {
        productID = ProProductID.from(infoPlistValue: bundle.object(forInfoDictionaryKey: ProProductID.infoPlistKey))
        self.fixedStatus = fixedStatus
        if let fixedStatus { status = fixedStatus }
    }

    static var launchArgumentStatus: ProStatus? {
        switch UserDefaults.standard.string(forKey: "SlidePilotProStatus") {
        case "locked": .locked
        case "unlocked": .unlocked
        default: nil
        }
    }
    #else
    init(bundle: Bundle = .main) {
        productID = ProProductID.from(infoPlistValue: bundle.object(forInfoDictionaryKey: ProProductID.infoPlistKey))
    }
    #endif

    isolated deinit {
        updatesTask?.cancel()
        refreshTask?.cancel()
    }

    /// Starts listening for transactions and checks the entitlements. Call once at launch, so
    /// no transaction (e.g. an approved Ask to Buy) is missed. Calling it again does nothing.
    func start() {
        guard updatesTask == nil else { return }
        #if DEBUG
        if fixedStatus != nil { return }
        #endif
        // Also delivers, once after launch, the transactions an earlier launch did not finish.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                await handle(update)
            }
        }
        refreshTask = Task { [weak self] in
            await self?.refreshStatus()
        }
    }

    /// Derives the status from StoreKit's current entitlements again. `currentEntitlements`
    /// leaves out refunded and revoked purchases; the Core rule checks the revocation as well.
    func refreshStatus() async {
        #if DEBUG
        if fixedStatus != nil { return }
        #endif
        // Read in a task of the store's own: a caller cancelled after a purchase (e.g. a closed
        // sheet) must not cut the list short and lock Pro again.
        var read = Task { await Self.currentEntitlements() }
        latestRead = read
        // Overlapping checks (launch, update, purchase, restore) finish in any order; only the
        // newest read may set the status, so an older answer never undoes a newer one. Every
        // caller waits for that newest read, so the status is current when this returns (e.g.
        // for Restore's "No Purchase Found").
        while true {
            let entitlements = await read.value
            guard let newest = latestRead, newest != read else {
                status = ProStatus(entitlements: entitlements, productID: productID)
                return
            }
            read = newest
        }
    }

    private static func currentEntitlements() async -> [ProEntitlement] {
        var entitlements: [ProEntitlement] = []
        for await result in Transaction.currentEntitlements {
            // An unverified transaction never unlocks Pro.
            guard case .verified(let transaction) = result else { continue }
            entitlements.append(ProEntitlement(transaction))
        }
        return entitlements
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
        return try await complete(product.purchase())
    }

    /// Finishes a purchase that StoreKit's own views made (`ProductView`), like `purchase()`.
    /// The offer handles their completion itself (`onInAppPurchaseCompletion`), so it passes
    /// each result here to verify, finish and check the entitlements.
    func completePurchase(_ result: Result<Product.PurchaseResult, any Error>) async throws -> ProPurchaseOutcome {
        try await complete(result.get())
    }

    private func complete(_ result: Product.PurchaseResult) async throws -> ProPurchaseOutcome {
        switch result {
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
        #if DEBUG
        // The simulator's StoreKit never answers outside Xcode; the button would stay disabled.
        if fixedStatus != nil { return }
        #endif
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
