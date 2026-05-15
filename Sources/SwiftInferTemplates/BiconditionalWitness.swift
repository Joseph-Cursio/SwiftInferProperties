import Foundation

/// V2.0 M7 — one detected Biconditional / iff witness: a Bool flag
/// paired with an Optional field whose presence should track the
/// flag (PRD §5.6).
///
/// **Pattern.** Either both fields are "active" or both are
/// "inactive." Examples from the PRD:
///   - `(isLoadingX: Bool, taskX: Task<_, _>?)` — spinner visible
///     iff request in flight.
///   - `(isShowingX: Bool, dataX: T?)` — view rendered iff data
///     present.
///
/// **What M7 detects.** Cartesian-product pairing of `is*` Bool
/// fields (whose names contain `Loading` / `Showing` / `Presenting`
/// / `Active` / `Fetching` / `Refreshing`) × all Optional fields in
/// the same State. v0.0 deliberately broad — PRD §5.6 calibration
/// note flags this as the trickiest of the five families, expecting
/// "cycles 3-5 worth of calibration to dial precision." Cartesian
/// pairing surfaces every plausible match; calibration narrows.
///
/// **Why Equatable State isn't required.** PRD §5.6 nuance: the
/// canonical biconditional pair contains a `Task<_, _>?` or
/// `AnyCancellable?` field, neither of which is `Equatable`. The
/// predicate (`state.<bool> == (state.<optional> != nil)`) operates
/// on *projected* Bool fields, both of which are always Equatable —
/// State-as-a-whole equality isn't needed for this family.
///
/// **What's deferred.**
///   - **Stem-matching pairing** (`isLoadingX` ↔ `taskX` / `dataX`).
///     v0.0 is Cartesian; stem-matching would tighten precision
///     but risks under-matching valid pairs that don't follow the
///     name convention.
///   - **Reducer-body strengthening signal** (PRD §5.6: "the
///     reducer body for `.startX` sets both and `.cancelX` clears
///     both — but at least one handler clears only one of the
///     pair"). Same body-walking deferral as M5 / M6.
public struct BiconditionalWitness: Sendable, Equatable, Codable {

    /// Name of the Bool field, e.g. `"isLoading"` / `"isShowingSheet"`.
    public let boolPropertyName: String

    /// Type-annotation text of the Bool field. Always `"Bool"` /
    /// `"Swift.Bool"` at detection (the detector filters by type),
    /// stored for rendering consistency.
    public let boolTypeName: String

    /// Name of the Optional field, e.g. `"activeTask"` / `"data"`.
    public let optionalPropertyName: String

    /// Type-annotation text of the Optional field, e.g. `"Task?"` /
    /// `"AnyCancellable?"` / `"Data?"`. Stored verbatim for the
    /// explainability block.
    public let optionalTypeName: String

    public init(
        boolPropertyName: String,
        boolTypeName: String,
        optionalPropertyName: String,
        optionalTypeName: String
    ) {
        self.boolPropertyName = boolPropertyName
        self.boolTypeName = boolTypeName
        self.optionalPropertyName = optionalPropertyName
        self.optionalTypeName = optionalTypeName
    }
}
