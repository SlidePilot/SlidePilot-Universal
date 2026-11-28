extension Optional {
    /// Whether there is a value; setting it to `false` clears the value. Drives the
    /// `isPresented` of an alert, sheet or file dialog from optional state:
    /// `isPresented: $failure.isPresented`.
    nonisolated var isPresented: Bool {
        get { self != nil }
        set {
            if !newValue { self = nil }
        }
    }
}
