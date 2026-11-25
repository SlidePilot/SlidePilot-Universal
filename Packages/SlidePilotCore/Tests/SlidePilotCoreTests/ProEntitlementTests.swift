import Foundation
import SlidePilotCore
import Testing

@Suite
struct ProEntitlementTests {
    let pro = "com.example.SlidePilot.pro"

    // PRO-02: no entitlement means Pro was never bought.
    @Test
    func noEntitlementIsLocked() {
        #expect(ProStatus(entitlements: [], productID: pro) == .locked)
    }

    @Test
    func purchaseUnlocks() {
        let entitlements = [ProEntitlement(productID: pro, ownership: .purchased)]
        #expect(ProStatus(entitlements: entitlements, productID: pro) == .unlocked)
    }

    // ADR 0020: Family Sharing is on, so a shared purchase counts.
    @Test
    func familySharedPurchaseUnlocks() {
        let entitlements = [ProEntitlement(productID: pro, ownership: .familyShared)]
        #expect(ProStatus(entitlements: entitlements, productID: pro) == .unlocked)
    }

    // PRO-02: a refunded or revoked purchase locks again.
    @Test(arguments: [ProEntitlement.Ownership.purchased, .familyShared])
    func revokedPurchaseLocks(_ ownership: ProEntitlement.Ownership) {
        let entitlements = [ProEntitlement(productID: pro, ownership: ownership, revocationDate: Date(timeIntervalSince1970: 0))]
        #expect(ProStatus(entitlements: entitlements, productID: pro) == .locked)
    }

    // A revoked family share does not hide the user's own purchase.
    @Test
    func validPurchaseNextToRevokedShareUnlocks() {
        let entitlements = [
            ProEntitlement(productID: pro, ownership: .familyShared, revocationDate: Date(timeIntervalSince1970: 0)),
            ProEntitlement(productID: pro, ownership: .purchased),
        ]
        #expect(ProStatus(entitlements: entitlements, productID: pro) == .unlocked)
    }

    @Test
    func otherProductDoesNotUnlock() {
        let entitlements = [ProEntitlement(productID: "com.example.Other.pro", ownership: .purchased)]
        #expect(ProStatus(entitlements: entitlements, productID: pro) == .locked)
    }

    // A refund reported by a transaction update locks, even while the current entitlements
    // still list the purchase without a revocation date.
    @Test
    func purchaseRevokedByUpdateLocks() {
        let entitlements = [ProEntitlement(productID: pro, ownership: .purchased, transactionID: 7)]
        #expect(ProStatus(entitlements: entitlements, productID: pro, revokedTransactionIDs: [7]) == .locked)
    }

    // Buying again after a refund is a new transaction and unlocks.
    @Test
    func newPurchaseAfterRevocationUnlocks() {
        let entitlements = [ProEntitlement(productID: pro, ownership: .purchased, transactionID: 8)]
        #expect(ProStatus(entitlements: entitlements, productID: pro, revokedTransactionIDs: [7]) == .unlocked)
    }

    @Test
    func missingProductIDNeverUnlocks() {
        let entitlements = [ProEntitlement(productID: pro, ownership: .purchased)]
        #expect(ProStatus(entitlements: entitlements, productID: nil) == .locked)
    }

    @Test
    func productIDFromInfoPlist() {
        #expect(ProProductID.from(infoPlistValue: pro) == pro)
        #expect(ProProductID.from(infoPlistValue: " \(pro)\n") == pro)
    }

    // The ID must come from the build; a missing, empty or unexpanded value is no product.
    @Test(arguments: [nil, "", "  ", "$(SLIDEPILOT_PRO_PRODUCT_ID)", "$(BUNDLE_ID_PREFIX).SlidePilot.pro"] as [String?])
    func invalidInfoPlistValueIsNoProductID(_ value: String?) {
        #expect(ProProductID.from(infoPlistValue: value) == nil)
    }

    @Test
    func nonStringInfoPlistValueIsNoProductID() {
        #expect(ProProductID.from(infoPlistValue: 42) == nil)
    }
}
