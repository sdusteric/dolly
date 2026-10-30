/// The editor window leaves the screen while the owner picks what to record, and comes back only
/// if they cancel. Once a recording starts, the take card brings it back.
nonisolated public struct EditorStepAside: Sendable {
    public enum Restore: Hashable, Sendable { case front, behind }

    private var pending: Restore?

    public init() {}

    /// Returns true when the window should hide now. A second call while it is already hidden keeps
    /// the first state.
    public mutating func hide(visible: Bool, active: Bool) -> Bool {
        guard visible else { return false }
        pending = active ? .front : .behind
        return true
    }

    /// The bar closed without a recording: where to put the window back, once.
    public mutating func cancelled() -> Restore? {
        defer { pending = nil }
        return pending
    }

    public mutating func started() { pending = nil }
}
