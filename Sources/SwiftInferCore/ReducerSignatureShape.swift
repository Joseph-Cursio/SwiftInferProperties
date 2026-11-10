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
