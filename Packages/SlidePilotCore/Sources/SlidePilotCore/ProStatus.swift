/// Whether this installation may use the features that SlidePilot Pro unlocks (PRO-01, ADR 0020).
///
/// The App Store build starts at `unknown` and the app sets `locked` or `unlocked` from
/// StoreKit's entitlements. The free Mac download is always `unlimited` and has no StoreKit code.
public enum ProStatus: Sendable, Equatable, CaseIterable {
    /// The entitlements have not been checked yet (App Store build, right after launch).
    case unknown
    /// Pro was not bought: audience output and remote control are a trial.
    case locked
    /// Pro was bought (or shared through Family Sharing).
    case unlocked
    /// The free Mac download: no limits, no trial, no purchase offer.
    case unlimited

    /// Whether every feature is available without a trial.
    public var unlocksEverything: Bool {
        switch self {
        case .unlocked, .unlimited: true
        case .unknown, .locked: false
        }
    }

    /// Whether `feature` runs as a trial. Both limited features follow the same rule (ADR 0020);
    /// the parameter keeps call sites explicit. An unknown status limits, so no output or
    /// connection runs unlimited before the entitlements are checked.
    public func limits(_ feature: LimitedFeature) -> Bool {
        !unlocksEverything
    }

    /// Whether the app shows the trial hint and the purchase offer (PRO-05). Only once the
    /// status is known to be locked, so a Pro user never sees them flash up after launch.
    public var showsTrialHint: Bool {
        self == .locked
    }
}

/// The features that are a trial without Pro (ADR 0020). Everything else (documents, presenter
/// view, notes, timer, pointer, drawing, curtain, settings) is never limited; the pointer,
/// drawing and curtain on an audience output are part of that output.
public enum LimitedFeature: String, Sendable, CaseIterable {
    /// An external display or AirPlay (iPad, iPhone), or any presentation window (Mac).
    case audienceOutput
    /// A remote connection, in either direction: controlling another device or being controlled.
    case remoteControl
}
