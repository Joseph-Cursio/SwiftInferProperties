/// V1.B — carrier-kind label inferred at reducer-discovery time. The
/// PRD §6.4 framing: discovery hands the rest of the v2.0 pipeline a
/// label distinguishing where the candidate came from, so downstream
/// scoring (M4+) and rendering know the carrier shape without
/// re-running the signature inspection.
///
/// **Cases:**
///   - `.generic` — signature-scan match (M1.A path) where the
///     enclosing context isn't a known TCA `Reducer` conformer. The
///     default and the catch-all.
///   - `.tca` — extracted from a TCA `Reducer` conformer's `var body:
///     some ReducerOf<Self>` (M1.B's conformance walk).
///   - `.elmStyle` — reserved for M1.C, which distinguishes free
///     `(S, A) -> S` reducers (Elm idiom — `func update(state:msg:)`)
///     from struct/class methods of the same signature. M1.B leaves
///     these in `.generic`.
///   - `.reSwift` — the ReSwift `(Action, State?) -> State` reducer
///     shape: Action-FIRST, Optional incoming State, non-optional
///     returned State. The reversed param order is why this needs its
///     own label rather than folding into `.elmStyle`.
///   - `.mobius` — the Mobius `(Model, Event) -> Next<Model, Effect>`
///     update shape: canonical `(State, Action)` order but an
///     effect-bearing `Next<…>` return rather than `Effect<…>` / a
///     tuple.
///   - `.workflow` — Square's Workflow `WorkflowAction.apply(toState:
///     inout State) -> Output?` — an arity-ONE method where the Action
///     is the enclosing type (`Self`), the single `inout` parameter is
///     State, and the optional `Output` is effect-like. The only carrier
///     whose Action is the receiver, not a parameter.
///
/// Labels are **informational** for discovery + §4 scoring — PRD §6.4:
/// "templates fire on all carrier kinds equally." The three framework
/// labels additionally gate measured-verify: `ActionSequenceStubEmitter`
/// rejects them (their call/return convention differs from the canonical
/// shapes; wiring the emit is separate, deferred work) so a discovered
/// ReSwift/Mobius/Workflow reducer is surfaced + scored but never
/// verified with a wrong-shaped call.
public enum ReducerCarrierKind: String, Sendable, Equatable, Codable, CaseIterable {
    case generic
    case tca
    case elmStyle = "elm-style"
    case reSwift = "reswift"
    case mobius
    case workflow

    /// The `Paradigm` this carrier maps to. TCA stays `.tca`; every other
    /// reducer family (Elm / ReSwift / Mobius / Workflow / generic) folds
    /// into the `.redux` family at this granularity. Single source of truth for
    /// the Redux distinctive-invariant analyzer.
    public var paradigm: Paradigm {
        switch self {
        case .tca: return .tca
        case .elmStyle, .reSwift, .mobius, .workflow, .generic: return .redux
        }
    }

    /// True for the `.redux`-family carriers — everything except TCA, which
    /// has its own richer invariant story. Gates the pure-reducer
    /// determinism / `unknownActionIsNoOp` candidates.
    public var isReduxFamily: Bool { paradigm == .redux }
}
