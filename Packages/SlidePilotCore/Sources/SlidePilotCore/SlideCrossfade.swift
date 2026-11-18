/// The crossfade between slides on the presentation screen (LAY-07).
public enum SlideCrossfade {
    /// The old app's duration, with ease-in-ease-out timing.
    public static let duration: Double = 0.6

    /// Whether a slide change fades: only when the setting is on and Reduce Motion is off.
    public static func isActive(setting: Bool, reduceMotion: Bool) -> Bool {
        setting && !reduceMotion
    }
}
