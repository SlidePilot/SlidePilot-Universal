import Foundation

/// Reports a system player's `isReadyForDisplay` (#141). `AVPlayerView` and
/// `AVPlayerViewController` are black until the first frame is ready, so the slide keeps
/// the player hidden over the PDF's poster until then.
final class MoviePlayerReadiness {
    /// Set by the representable on every update, so it always calls the current view.
    var changed: (Bool) -> Void = { _ in }

    private var observation: NSKeyValueObservation?
    private var isReady: Bool?
    /// Drops values still on their way from the previous player.
    private var generation = 0

    /// Watches `object`; reports its current value too.
    func observe<Object: NSObject>(_ object: Object, _ keyPath: KeyPath<Object, Bool>) {
        observation?.invalidate()
        isReady = nil
        generation += 1
        let generation = generation
        observation = object.observe(keyPath, options: [.initial, .new]) { @Sendable [weak self] _, change in
            guard let ready = change.newValue else { return }
            // KVO may call on any thread; this also defers the initial value, which arrives
            // while SwiftUI is still making the view. Hops may arrive out of order; that is
            // harmless because the slide only ever goes from hidden to shown.
            Task { @MainActor in self?.report(ready, generation: generation) }
        }
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        generation += 1
    }

    private func report(_ ready: Bool, generation: Int) {
        guard generation == self.generation, ready != isReady else { return }
        isReady = ready
        changed(ready)
    }
}
