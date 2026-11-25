import Foundation

/// The facts of one verified StoreKit transaction that decide the Pro status (PRO-02).
///
/// The app reads them from `Transaction.currentEntitlements`, so the rule stays testable
/// without StoreKit. Unverified transactions never become an entitlement.
public struct ProEntitlement: Sendable, Equatable {
    public enum Ownership: Sendable, Equatable {
        /// Bought with this Apple Account.
        case purchased
        /// Shared by a family member (ADR 0020: Family Sharing is on).
        case familyShared
    }

    public let productID: String
    public let ownership: Ownership
    /// Set when Apple revoked the purchase, e.g. after a refund or when the family organizer
    /// stopped sharing it.
    public let revocationDate: Date?

    public init(productID: String, ownership: Ownership, revocationDate: Date? = nil) {
        self.productID = productID
        self.ownership = ownership
        self.revocationDate = revocationDate
    }
}

extension ProStatus {
    /// The status of an App Store installation from its current entitlements: unlocked when
    /// one of them is a Pro transaction that was not revoked, purchased or family shared;
    /// otherwise locked. Without a valid product ID nothing can unlock Pro.
    public init(entitlements: some Sequence<ProEntitlement>, productID: String?) {
        guard let productID else {
            self = .locked
            return
        }
        let unlocks = entitlements.contains { $0.productID == productID && $0.revocationDate == nil }
        self = unlocks ? .unlocked : .locked
    }
}

/// The product ID of SlidePilot Pro as the build writes it into the Info.plist (PRO-02).
public enum ProProductID {
    /// The Info.plist key that carries the build setting `SLIDEPILOT_PRO_PRODUCT_ID`.
    public static let infoPlistKey = "SlidePilotProProductID"

    /// The product ID from the raw Info.plist value, or `nil` when the key is missing, empty or
    /// was not expanded by the build (still contains `$(`).
    public static func from(infoPlistValue value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !string.isEmpty, !string.contains("$(")
        else { return nil }
        return string
    }
}
