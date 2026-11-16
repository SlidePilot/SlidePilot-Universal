import SwiftUI

extension View {
    /// Shows the presentation, or the ready screen, on a connected external display
    /// (DOC-04, DOC-05 changed).
    ///
    /// iPadOS 27 no longer offers the external-display scene role to apps built with its SDK;
    /// they register a scene accessory on a view instead (hardware test on an iPad mini with
    /// iPadOS 27.2). iPadOS 26 keeps using the UIKit scene in ExternalDisplayScene.swift.
    /// Every view that registers shows the same content from the registry, so it does not
    /// matter which one the system picks.
    @ViewBuilder
    func presentsOnExternalDisplay(_ registry: SessionRegistry) -> some View {
        // Xcode 26 (Swift 6.2) has no iPadOS 27 SDK, so the accessory is compiled only by newer compilers.
        #if os(iOS) && compiler(>=6.4)
        if #available(iOS 27, *) {
            sceneAccessory {
                ExternalNonInteractiveAccessory {
                    ExternalDisplayView()
                        .environment(registry)
                }
                .onAvailabilityChange { isAvailable in
                    DiagnosticsLog.shared.record("ipad: external display accessory available: \(isAvailable)")
                }
            }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
