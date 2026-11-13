import SlidePilotRendering
import SwiftUI

#if os(iOS)
import UIKit

extension View {
    /// Shrinks the session's cache to the neighborhood when iPadOS reports memory pressure (ADR 0005).
    func shrinksOnMemoryWarning(_ session: PresentationSession) -> some View {
        task {
            let warnings = NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            )
            for await _ in warnings {
                // Read on every warning: a reload replaces the cache.
                await session.cache.shrinkToNeighborhood()
            }
        }
    }
}
#else
extension View {
    /// macOS has no memory warnings; the byte budget alone limits the cache.
    func shrinksOnMemoryWarning(_ session: PresentationSession) -> some View {
        self
    }
}
#endif
