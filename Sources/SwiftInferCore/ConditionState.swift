/// Whether a package manifest sets a compilation condition, as far as reading its syntax can tell.
public enum ConditionState: Sendable, Equatable {
    /// The build sets the condition.
    case set
    /// The build does not set it.
    case unset
    /// The manifest may or may not set it: a define under a manifest-level branch, or one whose
    /// gate the reader cannot evaluate. `#if` keeps both branches on it.
    case undecided

    /// The condition's truth value, with `undecided` answered by `fallback`.
    public func isSet(otherwise fallback: Bool) -> Bool {
        switch self {
        case .set: true
        case .unset: false
        case .undecided: fallback
        }
    }
}
