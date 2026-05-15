import Foundation

/// V2.0 M1.A — value type representing one detected reducer-shaped
/// function. The output unit of `ReducerDiscoverer` and the input unit
/// for every later v2.0 milestone (M2 generates Action sequences for
/// the candidate's Action type; M3 verifies invariants against its
/// reducer body; M4–M7 score interaction-template families on it).
///
/// **M1.A scope: signature-only.** This value records what the
/// signature looks like — three field names (state, action, function)
/// plus a location and the matched canonical shape. It does NOT yet
/// carry:
///
///   - A carrier-kind label (`.tca` / `.elmStyle` / `.generic`) —
///     that's M1.C, after the TCA `Reducer.body` walk lands at M1.B
///     and we know whether `.tca` ever applies.
///   - Equatable / Sendable / Hashable conformance signals on State
///     or Action — those are §4 scoring inputs at M4+.
///   - Pin-vs-list disambiguation — `--reducer <module>.<typeName>.<funcName>`
///     pinning lives at M1.C alongside the carrier-kind work.
///
/// The value stays minimal to match v1's "the scanner emits one record
/// per matched syntactic shape; downstream stages enrich it"
/// convention (mirrors `FunctionSummary` / `IdentityCandidate` /
/// `TypeDecl` in `FunctionScanner.swift`).
public struct ReducerCandidate: Sendable, Equatable, Codable {

    /// Source location of the function declaration, in
    /// `<path>:<line>` form — mirrors v1's `FunctionSummary.location`
    /// shape so the rendered output threads through the same
    /// "file:line click target" UX.
    public let location: String

    /// Name of the enclosing type if the function is an instance /
    /// static method (`"Inbox"`, `"AppLogic"`, etc.); `nil` for
    /// free functions at file scope. M1.A treats both equally — the
    /// downstream pipelines (M3 verify, M4+ templates) consume both
    /// kinds. Carrier-kind inference at M1.C may use this signal to
    /// distinguish `.elmStyle` (free function) from `.tca` /
    /// `.generic` (method).
    public let enclosingTypeName: String?

    /// The function's own name (`"reduce"`, `"update"`, `"body"`,
    /// `"handle"`, etc.). M1.A does NOT filter on function name — a
    /// reducer is anything matching the canonical signature, even if
    /// it's named `foo`. Vocabulary-based filtering (favor names like
    /// `reduce` / `update`) is a §4 scoring signal at M4+.
    public let functionName: String

    /// The matched canonical signature shape — see
    /// `ReducerSignatureShape`. Downstream pipelines branch on this:
    /// `(inout S, A) -> Void` requires an in-place verify wrapper
    /// (copy-then-call); `(S, A) -> S` calls directly; `(S, A) ->
    /// (S, Effect<A>)` routes to the §7.3 subprocess verify path.
    public let signatureShape: ReducerSignatureShape

    /// The State type's textual name as it appears in source
    /// (`"Inbox.State"`, `"AppState"`, `"State"`, etc.). M1.A does
    /// NOT resolve this to a `TypeDecl` record — that's an M3 / M4
    /// concern when `Equatable` conformance + projected-field
    /// resolution matter. The name is preserved verbatim for
    /// rendering.
    public let stateTypeName: String

    /// The Action type's textual name as it appears in source
    /// (`"Inbox.Action"`, `"AppAction"`, etc.). Same posture as
    /// `stateTypeName` — verbatim for M1.A, resolved at M2+ when
    /// the Action-sequence generator needs to enumerate cases.
    public let actionTypeName: String

    public init(
        location: String,
        enclosingTypeName: String?,
        functionName: String,
        signatureShape: ReducerSignatureShape,
        stateTypeName: String,
        actionTypeName: String
    ) {
        self.location = location
        self.enclosingTypeName = enclosingTypeName
        self.functionName = functionName
        self.signatureShape = signatureShape
        self.stateTypeName = stateTypeName
        self.actionTypeName = actionTypeName
    }

    /// Fully-qualified name `<enclosingType>.<functionName>` (or just
    /// `<functionName>` for free functions). Used for the rendered
    /// output and for the `--reducer` pin flag (M1.C).
    public var qualifiedName: String {
        if let enclosingTypeName {
            return "\(enclosingTypeName).\(functionName)"
        }
        return functionName
    }
}

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
}
