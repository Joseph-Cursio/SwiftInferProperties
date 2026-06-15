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
    /// kinds. M1.C uses this signal to distinguish `.elmStyle` (free
    /// function) from `.generic` (method on a non-Reducer type).
    public let enclosingTypeName: String?

    /// The function's own name (`"reduce"`, `"update"`, `"body"`,
    /// `"handle"`, etc.). M1.A does NOT filter on function name — a
    /// reducer is anything matching the canonical signature, even if
    /// it's named `foo`. Vocabulary-based filtering (favor names like
    /// `reduce` / `update`) is a §4 scoring signal at M4+. TCA
    /// candidates (M1.B) use the synthetic name `"body"` since the
    /// closure isn't a declared function.
    public let functionName: String

    /// The matched canonical signature shape — see
    /// `ReducerSignatureShape`. Downstream pipelines branch on this:
    /// `(inout S, A) -> Void` requires an in-place verify wrapper
    /// (copy-then-call); `(S, A) -> S` calls directly; `(S, A) ->
    /// (S, Effect<A>)` routes to the §7.3 subprocess verify path;
    /// `(inout S, A) -> Effect<A>` is the synthesized TCA-closure
    /// shape (M1.B) and routes the same as the tuple form.
    public let signatureShape: ReducerSignatureShape

    /// The State type's textual name as it appears in source
    /// (`"Inbox.State"`, `"AppState"`, `"State"`, etc.). M1.A does
    /// NOT resolve this to a `TypeDecl` record — that's an M3 / M4
    /// concern when `Equatable` conformance + projected-field
    /// resolution matter. The name is preserved verbatim for
    /// rendering. M1.B's TCA path synthesizes
    /// `"<EnclosingType>.State"` from the conventional TCA shape
    /// (the conforming type has nested `State` / `Action` types).
    public let stateTypeName: String

    /// The Action type's textual name as it appears in source
    /// (`"Inbox.Action"`, `"AppAction"`, etc.). Same posture as
    /// `stateTypeName` — verbatim for M1.A, synthesized as
    /// `"<EnclosingType>.Action"` for M1.B's TCA path.
    public let actionTypeName: String

    /// V1.B — carrier-kind label inferred at discovery time. M1.A
    /// candidates default to `.generic` (signature-scan); M1.B's TCA
    /// path emits `.tca`; M1.C distinguishes `.elmStyle` (free
    /// function) from `.generic`. The label is informational —
    /// downstream pipelines (M3 verify, M4+ scoring) consume it for
    /// routing and rendering decisions, not as a hard filter.
    public let carrierKind: ReducerCarrierKind

    /// V2.0 M8.B — body-purity classification (`.pure` /
    /// `.effectBearing` / `.hiddenMutability`) computed by
    /// `ReducerPurityAnalyzer` at discovery time. Drives M8's verify
    /// routing: `.hiddenMutability` is rejected (non-deterministic
    /// across action sequences); `.pure` + `.effectBearing` both run
    /// through M3.E (the emit shape differs per signature). Defaults
    /// to `.pure` for older JSON records (none on disk yet).
    public let purity: ReducerPurity

    /// Cycle 122 (Phase A) → cycle 125 (Phase B) — the Action enum's
    /// cases, in source order, captured at discovery time for `.tca`
    /// carriers (real TCA Actions don't declare `CaseIterable`, so the
    /// verifier enumerates them explicitly). Each case carries its
    /// associated-value payload types (empty = payload-free). Phase B's
    /// relaxed partial-exploration emitter builds a generator over the
    /// *constructible* subset (payload-free + raw-payload cases) and
    /// discloses the rest as excluded; the all-or-nothing Phase A gate is
    /// gone. Empty for non-`.tca` carriers and older records.
    public let actionCases: [ActionCaseInfo]

    public init(
        location: String,
        enclosingTypeName: String?,
        functionName: String,
        signatureShape: ReducerSignatureShape,
        stateTypeName: String,
        actionTypeName: String,
        carrierKind: ReducerCarrierKind = .generic,
        purity: ReducerPurity = .pure,
        actionCases: [ActionCaseInfo] = []
    ) {
        self.location = location
        self.enclosingTypeName = enclosingTypeName
        self.functionName = functionName
        self.signatureShape = signatureShape
        self.stateTypeName = stateTypeName
        self.actionTypeName = actionTypeName
        self.carrierKind = carrierKind
        self.purity = purity
        self.actionCases = actionCases
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

    /// V1.91 (cycle-88 fix for cycle-87 finding #2) — fully-qualified
    /// State type name. Used by the witness detectors to scope the
    /// type-stack suffix match to the candidate's *own* State, not
    /// any same-named State elsewhere in the corpus. Without this,
    /// every reducer following the `Reducer.State` convention would
    /// fire witnesses against every other reducer's State (cycle-87
    /// measured 8.2× witness inflation on the hand-rolled corpus).
    ///
    /// **Dot-awareness.** M1.A's signature scan stores bare
    /// `stateTypeName` (`"State"`) so this property prefixes the
    /// enclosing type. M1.B's TCA closure walker already pre-
    /// qualifies as `"<enclosingType>.State"` (the literal text is
    /// load-bearing for downstream stub emission — see
    /// `ActionSequenceStubEmitter`'s `\(stateTypeName)()`
    /// constructor); when `stateTypeName` already contains a dot,
    /// return it as-is to avoid double-qualifying.
    public var stateQualifiedName: String {
        Self.qualify(typeName: stateTypeName, enclosing: enclosingTypeName)
    }

    /// V1.91 (cycle-88 fix for cycle-87 finding #2) — sister to
    /// `stateQualifiedName` for the Action enum. Same mechanism, same
    /// rationale: `IdempotenceWitnessDetector` walks the syntax tree
    /// looking for an enum named `actionTypeName`, and when every
    /// reducer follows the `Reducer.Action` convention the bare-
    /// `Action` match fires against every reducer's Action. Cycle-87
    /// measurement showed idempotence at 49 suggestions vs designed
    /// 9 — the same ~8× inflation factor as State.
    public var actionQualifiedName: String {
        Self.qualify(typeName: actionTypeName, enclosing: enclosingTypeName)
    }

    private static func qualify(typeName: String, enclosing: String?) -> String {
        // Already-qualified names (containing a dot) come from M1.B's
        // TCA walker, which pre-qualifies for stub-emission reasons.
        // Pass them through untouched.
        if typeName.contains(".") {
            return typeName
        }
        if let enclosing {
            return "\(enclosing).\(typeName)"
        }
        return typeName
    }

    // MARK: - Codable (carrierKind backward-compat default)

    private enum CodingKeys: String, CodingKey {
        case location
        case enclosingTypeName
        case functionName
        case signatureShape
        case stateTypeName
        case actionTypeName
        case carrierKind
        case purity
        case actionCases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.location = try container.decode(String.self, forKey: .location)
        self.enclosingTypeName = try container.decodeIfPresent(String.self, forKey: .enclosingTypeName)
        self.functionName = try container.decode(String.self, forKey: .functionName)
        self.signatureShape = try container.decode(ReducerSignatureShape.self, forKey: .signatureShape)
        self.stateTypeName = try container.decode(String.self, forKey: .stateTypeName)
        self.actionTypeName = try container.decode(String.self, forKey: .actionTypeName)
        // Backward-compat: pre-M1.B records (none exist on disk yet but
        // forward-defending the schema) default to `.generic`.
        self.carrierKind = try container.decodeIfPresent(
            ReducerCarrierKind.self,
            forKey: .carrierKind
        ) ?? .generic
        // M8.B — pre-M8 records default to `.pure` (the safe-to-route
        // value; pure reducers go through the same M3.E path).
        self.purity = try container.decodeIfPresent(
            ReducerPurity.self,
            forKey: .purity
        ) ?? .pure
        // Cycle 122/125 — pre-Phase-A records (and all non-`.tca`
        // carriers) default to an empty case list.
        self.actionCases = try container.decodeIfPresent(
            [ActionCaseInfo].self,
            forKey: .actionCases
        ) ?? []
    }
}

/// Cycle 125 (Phase B) — one Action enum case captured at discovery time:
/// its name plus its associated-value payload types in declaration order
/// (`[]` = payload-free). The emitter classifies constructibility from
/// `payloadTypes` (empty → free; single recognized raw type → raw-payload;
/// anything else → non-derivable, excluded from partial exploration).
public struct ActionCaseInfo: Sendable, Equatable, Codable {
    public let name: String
    public let payloadTypes: [String]

    public init(name: String, payloadTypes: [String] = []) {
        self.name = name
        self.payloadTypes = payloadTypes
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
/// **Three cases, two shipped at M1.B:**
///   - `.generic` — signature-scan match (M1.A path) where the
///     enclosing context isn't a known TCA `Reducer` conformer. The
///     default and the catch-all.
///   - `.tca` — extracted from a TCA `Reducer` conformer's `var body:
///     some ReducerOf<Self>` (M1.B's conformance walk).
///   - `.elmStyle` — reserved for M1.C, which distinguishes free
///     `(S, A) -> S` reducers (Elm idiom — `func update(state:msg:)`)
///     from struct/class methods of the same signature. M1.B leaves
///     these in `.generic`.
///
/// Labels are **informational** — PRD §6.4: "templates fire on all
/// carrier kinds equally." Pipeline routing (`verifyPath`,
/// `actionGeneratorSource`) lives on later milestones' fields, not
/// here.
public enum ReducerCarrierKind: String, Sendable, Equatable, Codable, CaseIterable {
    case generic
    case tca
    case elmStyle = "elm-style"
}
