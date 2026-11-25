/// The look of the app's windows, chosen in Settings > General (SET-05).
///
/// The presentation window and the ready screen keep their fixed dark look.
public enum AppAppearance: String, CaseIterable, Sendable {
    /// Follows the system setting.
    case system
    case light
    case dark

    public static let `default` = AppAppearance.system
}
