import Foundation

/// V2.0 M5 — one detected Cardinality witness inside a reducer's
/// State struct: ≥ 2 stored fields that look like mutually-exclusive
/// presentation flags / sheets / alerts (PRD §5.4).
///
/// **What M5 detects (and what it doesn't).**
///
/// Two field shapes feed the witness:
///
///   - **Boolean presentation flags.** Stored `Bool` properties whose
///     name matches `is(Showing|Presenting).*` or contains `Showing`
///     / `Presenting`. Indicator: `state.<name>` evaluates to `true`
///     when active.
///   - **Optional presentation values.** Stored `T?` (or `Optional<T>`)
///     properties whose lowercased name contains `sheet`, `alert`,
///     `fullscreencover`, or `popover`. Indicator:
///     `state.<name> != nil` when active.
///
/// **One witness per State**, not Cartesian-product per field —
/// the cardinality invariant is "across **all** of these, at most
/// one is active simultaneously," so we collect every detected field
/// and assert `count <= 1` once.
///
/// **What's deferred to calibration cycles.**
///
///   - **Reducer-body strengthening.** PRD §5.4's third witness ("the
///     reducer body for the corresponding `.show*` actions writes
///     `true` / `.some(...)` to one without clearing the others") is
///     a *strengthening* signal that bumps the score. M5 doesn't yet
///     walk the body — that's the same body-walking surface PRD §4.1
///     reserves for M5+ refinements.
///   - **Threshold tuning.** PRD §5.4 calibration note: the "≥ 2
///     fields" heuristic is intentionally crude as a starting point.
///     v2.0 ships at default `.possible` visibility (PRD §3.5
///     corollary); calibration may raise the threshold or refine
///     the name patterns.
public struct CardinalityWitness: Sendable, Equatable, Codable {

    /// V2.0 M5 — one matching presentation field in the State
    /// struct. `propertyName` is the source-level name; `indicator`
    /// is the Swift-source `Bool` expression evaluating to `true`
    /// when the field is "active" (`state.<name>` for Bools,
    /// `state.<name> != nil` for Optionals).
    public struct Field: Sendable, Equatable, Codable {
        public let propertyName: String
        public let indicator: String
        public let kind: CardinalityFieldKind

        public init(propertyName: String, indicator: String, kind: CardinalityFieldKind) {
            self.propertyName = propertyName
            self.indicator = indicator
            self.kind = kind
        }
    }

    /// The detected presentation fields. By construction `≥ 2`
    /// when a witness is emitted — fewer doesn't surface a witness.
    public let fields: [Field]

    public init(fields: [Field]) {
        self.fields = fields
    }
}

/// V2.0 M5 — classification for one Cardinality field. Hoisted to
/// file scope to satisfy SwiftLint's 1-level nesting cap; `Field` is
/// already nested inside `CardinalityWitness`.
public enum CardinalityFieldKind: String, Sendable, Equatable, Codable, CaseIterable {
    case boolFlag = "bool-flag"
    case optionalPresentation = "optional-presentation"
}
