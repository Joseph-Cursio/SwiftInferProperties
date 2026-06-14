import Foundation

/// V2.0 M4.A — one inferred interaction-invariant candidate. The
/// output unit of the M4+ template engine and the input unit for
/// every downstream stage (M4.D embeds the predicate into M3.B's
/// stub; M3.E's verify pipeline runs the embedded predicate;
/// `swift-infer discover-interaction` renders these as tiered
/// suggestions).
///
/// **Why this is its own type, not a `Suggestion` subtype.** v1's
/// `Suggestion` is the algebraic-suggestion shape (round-trip,
/// idempotence, semigroup, etc.) with fields keyed on the function
/// pair / template arm. v2.0's interaction invariants key on a
/// reducer candidate + a family + a Swift-source predicate — a
/// different shape with a different rendering / scoring / verify
/// path. Folding them into one type would muddy both ends.
///
/// **Identity stability.** Computed from
/// `(family.rawValue, reducer.qualifiedName, predicate)` via the
/// existing `SuggestionIdentity` SHA256-prefix derivation. Same
/// 16-char hex display form as v1 so the §17 metrics arc joins
/// directly when schema v4 ships.
public struct InteractionInvariantSuggestion: Sendable, Equatable, Codable {

    /// Stable identity hash for the §17 metrics arc + the
    /// `--reducer` pin / accept-flow plumbing. Same shape as v1's
    /// `SuggestionIdentity` (16-char uppercase hex, `0x` prefix on
    /// display, stripped on normalized) so the existing
    /// SemanticIndex / decisions.json / verify-evidence join pattern
    /// extends.
    public let identity: SuggestionIdentity

    /// Which of the five PRD §5 interaction-invariant families this
    /// suggestion belongs to. M4 ships Conservation + Idempotence
    /// (lifted from v1); M5–M7 add Cardinality, Referential
    /// integrity, Biconditional.
    public let family: InteractionInvariantFamily

    /// `reducerQualifiedName`, `reducerLocation`, `stateTypeName`,
    /// and `actionTypeName` are copied from the source `ReducerCandidate`
    /// so the suggestion is self-describing without a join. Callers
    /// that need the full `ReducerCandidate` re-load it from the
    /// SemanticIndex (or in v2.0's not-yet-shipped equivalent) keyed
    /// by `reducerQualifiedName`.
    public let reducerQualifiedName: String
    public let reducerLocation: String
    public let stateTypeName: String
    public let actionTypeName: String

    /// Swift-source predicate the M4.D stub emitter will embed into
    /// the verifier as `#expect(<predicate>)` per generated action.
    /// Example: `"state.total == state.items.map(\\.price).reduce(0, +)"`
    /// for a Conservation invariant. The predicate's free variable
    /// is `state` — the closure parameter the stub binds at each
    /// step.
    public let predicate: String

    /// V1-shape score. Same 0..N+ integer scale as the v1
    /// `Suggestion.score`, fed by the §4.1 per-family signals from
    /// PRD v2.0.
    public let score: Int

    /// Effective tier. Set by the M4+ template engine per the §4.2
    /// score → tier mapping (≥75 strong, 40–74 likely, 20–39
    /// possible, <20 suppressed). PRD §3.5 corollary: every new
    /// family ships at default `.possible` visibility through three
    /// calibration cycles, so M4.B/C's scoring weights are
    /// deliberately tuned to land in the `.possible` range until
    /// promotion.
    public let tier: Tier

    /// "Why suggested" bullet points per PRD §4.5 — one per active
    /// signal that contributed to the score. Rendered in the
    /// `discover-interaction` explainability block.
    public let whySuggested: [String]

    /// "Why this might be wrong" bullet points per PRD §4.5 —
    /// active counter-signals + known limitations (e.g.
    /// floating-point round-off, action enum size, edge cases the
    /// generator might not cover).
    public let whyMightBeWrong: [String]

    /// Wall-clock time the suggestion was first emitted. ISO8601-
    /// encoded in JSON. Used by §17.2's time-to-adoption metric
    /// (decision timestamp − firstSeenAt) — same anchor v1.71 wired
    /// for algebraic suggestions via the SemanticIndex.
    public let firstSeenAt: Date

    public init(
        identity: SuggestionIdentity,
        family: InteractionInvariantFamily,
        reducerQualifiedName: String,
        reducerLocation: String,
        stateTypeName: String,
        actionTypeName: String,
        predicate: String,
        score: Int,
        tier: Tier,
        whySuggested: [String],
        whyMightBeWrong: [String],
        firstSeenAt: Date
    ) {
        self.identity = identity
        self.family = family
        self.reducerQualifiedName = reducerQualifiedName
        self.reducerLocation = reducerLocation
        self.stateTypeName = stateTypeName
        self.actionTypeName = actionTypeName
        self.predicate = predicate
        self.score = score
        self.tier = tier
        self.whySuggested = whySuggested
        self.whyMightBeWrong = whyMightBeWrong
        self.firstSeenAt = firstSeenAt
    }

    /// V2.0 M4.A — convenience constructor that derives `identity`
    /// from the canonical input `(family, reducer, predicate)`.
    /// Used by every template emitter so the identity-hash derivation
    /// stays consistent across families.
    public static func identityCanonicalInput(
        family: InteractionInvariantFamily,
        reducerQualifiedName: String,
        predicate: String
    ) -> String {
        "\(family.rawValue)::\(reducerQualifiedName)::\(predicate)"
    }
}

/// V2.0 M4.A — the five interaction-invariant families from PRD §5.
/// All five ship in the enum at M4.A; the *templates* that fire on
/// each family ship across M4–M7:
///
///   - `conservation` — M4 (lifted from v1). Stored aggregate that
///     should equal the recomputation from a contributing collection.
///   - `idempotence` — M4 (lifted from v1). Applying-twice an Action
///     case equals applying-once.
///   - `cardinality` — M5. At most one transient-presentation flag
///     active.
///   - `referentialIntegrity` — M6. Selected ID exists in extant
///     collection.
///   - `biconditional` — M7. Two State fields that should be
///     either both-set or both-unset.
///
/// Raw values are stable strings so downstream consumers (the
/// `discover-interaction` render path, the §17 metrics arc once
/// schema v4 ships) can key on them.
public enum InteractionInvariantFamily: String, Sendable, Equatable, Codable, CaseIterable {
    case conservation
    case idempotence
    case cardinality
    case referentialIntegrity = "referential-integrity"
    case biconditional
}

public extension InteractionInvariantFamily {

    /// V2.0 Finding G — the SwiftProjectLint refactor lint a family
    /// cross-references, or `nil` if the family carries no re-home.
    ///
    /// Finding G (cycle 104) established that Cardinality and
    /// Biconditional detect a **representable illegal state** — a
    /// SwiftSyntax-AST smell that SwiftProjectLint already lints
    /// (`mutually-exclusive-presentation-state`, `flag-optional-pair-state`).
    /// The detector is *not* wrong: the State shape it matches is real.
    /// But the inferred *invariant* holds at only 33–50% acceptance as a
    /// runtime property (the corpus showed the predicate can be false at
    /// rest for orthogonal fields, or enforced at a presentation layer the
    /// generated test doesn't model), so the generated test can false-fail
    /// without a real bug.
    ///
    /// Per the cycle-104 decision we **keep emitting the property** (a
    /// failing test may still surface a genuine unguarded illegal state —
    /// the detector can't tell the two apart) but **never promote it past
    /// `.possible`** and cross-reference the lint in the suggestion's
    /// "why this might be wrong" block. This property is the single source
    /// of both the cross-reference rule name *and* the promotion gate:
    /// a non-nil value means "pin at `.possible`, do not promote." Any
    /// future interaction-suggestion score→tier promotion path must
    /// consult it.
    var swiftProjectLintDeferral: String? {
        switch self {
        case .cardinality:
            return "mutually-exclusive-presentation-state"

        case .biconditional:
            return "flag-optional-pair-state"

        case .conservation, .idempotence, .referentialIntegrity:
            return nil
        }
    }
}
