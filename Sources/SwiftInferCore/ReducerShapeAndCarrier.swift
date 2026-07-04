import Foundation

// V2.0 M1.A / V1.B — the reducer signature-shape + carrier-kind enums,
// lifted out of `ReducerCandidate.swift` for the `file_length` cap.
// Pure relocation — no behavior change.

/// V2.0 M1.A — the three canonical reducer signature shapes from PRD
/// §6.2 plus a `(S, A) -> (S, Effect<A>)` tuple-return shape.
///
/// `Effect<A>` recognition (3rd case) is **name-based only** at M1.A:
/// the signature scanner matches the textual return type without
/// resolving `Effect` to a real type. Cross-import correctness (does
/// the user actually import a library that defines `Effect`?) is the
/// caller's responsibility — false matches here surface in calibration
/// and are why §3.5 mandates default-`Possible` visibility for every
/// new template family.
///
/// Raw values are stable across schema versions — downstream consumers
/// (M3+ verify, M4+ scoring, eventually a serialized form for the
/// SemanticIndex) key on them.
public enum ReducerSignatureShape: String, Sendable, Equatable, Codable, CaseIterable {
    /// `(S, A) -> S` — Elm-style, hand-rolled, or free-function
    /// reducer. The simplest shape; in-process verifiable when State
    /// is Equatable and the body has no Effect / async / Task
    /// references.
    case stateActionReturnsState = "state-action-returns-state"

    /// `(inout S, A) -> Void` — common idiom in TCA `Reduce` closures
    /// and many hand-rolled reducers. In-process verify wraps the
    /// call site (copies State, mutates the copy, returns it) so the
    /// same outcome vocabulary applies.
    case inoutStateActionReturnsVoid = "inout-state-action-returns-void"

    /// `(S, A) -> (S, Effect<A>)` — TCA pre-2022 idiom, ReSwift with
    /// thunks. The `Effect<A>` half is captured-and-discarded at
    /// verify time (§16 #1 hard guarantee — no user-side Effects run
    /// in-process). Effect-bearing reducers route to the §7.3
    /// subprocess verify path.
    case stateActionReturnsStateAndEffect = "state-action-returns-state-and-effect"

    /// V1.B — `(inout S, A) -> Effect<A>` — the synthesized signature
    /// for TCA `Reduce { state, action in ... }` closures inside a
    /// `Reducer` conformer's `var body: some ReducerOf<Self>`. The
    /// closure isn't a `FunctionDeclSyntax`, so M1.B's TCA walk
    /// synthesizes this shape from the closure's source position +
    /// the enclosing type's `Self.State` / `Self.Action` convention.
    /// Routes to the §7.3 subprocess verify path by default; pure
    /// closures (no `.run` / `.send` / `.cancel` references) qualify
    /// for the in-process path at M3+.
    case inoutStateActionReturnsEffect = "inout-state-action-returns-effect"
}

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
    /// into the `.redux` family at this granularity. Single source of truth
    /// shared by `ReducerCandidate.asStatefulRole()` and the Redux
    /// distinctive-invariant analyzer.
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
