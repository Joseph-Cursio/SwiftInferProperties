import SwiftInferCore

/// One action dispatched inside a TCA `TestStore` test — the atom of a
/// mined trace (TestStore Trace Mining, Slice 1). Captured verbatim from
/// `store.send(.case(args))` / `store.receive(.case(args))`.
///
/// The `argumentTexts` split is load-bearing for downstream consumption:
/// a **payload-free** action (`.dismiss`) is reconstructible in a
/// standalone verifier as `.dismiss`, whereas a **payload-bearing** one
/// (`.select(a.id)`) carries argument source text that references
/// test-body-local bindings the verifier doesn't have — so Slice 2's
/// replay-then-extend emits only the payload-free subset, and payload
/// generalization is deferred (see `docs/teststore-trace-mining-build-plan.md`).
public struct MinedAction: Equatable, Sendable {

    /// Whether the action was *sent* (user-driven) or *received*
    /// (an effect output). Only `.send` feeds the user-action corpus;
    /// `.receive` is recorded separately (replaying an effect output as a
    /// user action would be wrong — proposal open-Q #1).
    public enum Kind: Equatable, Sendable {
        case send
        case receive
    }

    public let kind: Kind

    /// The enum case name — `"select"` from `.select(a.id)`,
    /// `"dismiss"` from `.dismiss`.
    public let caseName: String

    /// The verbatim source text of each associated-value argument, in
    /// order. Empty for a payload-free action.
    public let argumentTexts: [String]

    public var isPayloadFree: Bool { argumentTexts.isEmpty }

    public init(kind: Kind, caseName: String, argumentTexts: [String]) {
        self.kind = kind
        self.caseName = caseName
        self.argumentTexts = argumentTexts
    }
}

/// The ordered actions dispatched through one `TestStore` in one test
/// method — a developer-authored, semantically-meaningful action
/// ordering (TestStore Trace Mining, Slice 1).
///
/// `reducerTypeName` is the join key to a `ReducerCandidate`
/// (`enclosingTypeName == reducerTypeName`); `initialStateExpr` is
/// captured for Slice 3's initial-state mining and unused by the
/// payload-free replay slice.
public struct MinedActionTrace: Equatable, Sendable {

    /// The reducer type constructed in the store — `"Feature"` from
    /// `TestStore(initialState:) { Feature() }` or a `reducer:` argument.
    /// `nil` when the construction couldn't be resolved (the bare-`store`
    /// fallback path).
    public let reducerTypeName: String?

    /// The verbatim `TestStore(initialState:)` argument text
    /// (`"Feature.State(items: [a, b])"`), or `nil` when absent. Slice 3
    /// fodder; not consumed by the payload-free replay slice.
    public let initialStateExpr: String?

    /// `.send` actions in source order — the user-action corpus.
    public let sent: [MinedAction]

    /// `.receive` actions in source order — effect outputs, kept
    /// separate from `sent` (see `MinedAction.Kind`).
    public let received: [MinedAction]

    /// The enclosing test method's source location.
    public let location: SwiftInferCore.SourceLocation

    public init(
        reducerTypeName: String?,
        initialStateExpr: String?,
        sent: [MinedAction],
        received: [MinedAction],
        location: SwiftInferCore.SourceLocation
    ) {
        self.reducerTypeName = reducerTypeName
        self.initialStateExpr = initialStateExpr
        self.sent = sent
        self.received = received
        self.location = location
    }
}
