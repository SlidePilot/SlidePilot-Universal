import Observation

/// Applies an appearance to the app's windows (SET-05).
///
/// The app provides one per platform: `NSApp.appearance` on the Mac and the window
/// scenes' trait overrides on iPad and iPhone.
@MainActor
public protocol AppearanceApplying: AnyObject {
    func apply(_ appearance: AppAppearance)
}

/// Follows the Appearance setting (SET-05) for as long as it lives.
///
/// The app owns one for its whole run. The windows switch as soon as the setting changes.
@MainActor
public final class AppearanceKeeper {
    private let applier: any AppearanceApplying
    private var observation: Task<Void, Never>?

    public init(settings: AppSettings, applier: any AppearanceApplying) {
        self.applier = applier
        // Applied right away, so the first window opens in the chosen appearance.
        applier.apply(settings.appearance)
        observation = Task { [applier] in
            for await appearance in Observations({ settings.appearance }) {
                guard !Task.isCancelled else { break }
                applier.apply(appearance)
            }
        }
    }

    isolated deinit {
        observation?.cancel()
    }
}
