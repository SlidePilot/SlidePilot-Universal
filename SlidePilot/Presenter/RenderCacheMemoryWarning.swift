import SlidePilotRendering
import SwiftUI

#if os(iOS)
import UIKit

extension View {
    /// Shrinks the cache to the neighborhood when iPadOS reports memory pressure (ADR 0005).
    func shrinksOnMemoryWarning(_ cache: RenderCache) -> some View {
        task {
            let warnings = NotificationCenter.default.notifications(
                named: UIApplication.didReceiveMemoryWarningNotification
            )
            for await _ in warnings {
                await cache.shrinkToNeighborhood()
            }
        }
    }
}
#else
extension View {
    /// macOS has no memory warnings; the byte budget alone limits the cache.
    func shrinksOnMemoryWarning(_ cache: RenderCache) -> some View {
        self
    }
}
#endif
