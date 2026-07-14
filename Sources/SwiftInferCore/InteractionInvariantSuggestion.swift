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
    public var identity: SuggestionIdentity

    /// Which of the five PRD §5 interaction-invariant families this
    /// suggestion belongs to. M4 ships Conservation + Idempotence
    /// (lifted from v1); M5–M7 add Cardinality, Referential
    /// integrity, Biconditional.
    public var family: InteractionInvariantFamily

    /// `reducerQualifiedName`, `reducerLocation`, `stateTypeName`,
    /// and `actionTypeName` are copied from the source `ReducerCandidate`
    /// so the suggestion is self-describing without a join. Callers
    /// that need the full `ReducerCandidate` re-load it from the
    /// SemanticIndex (or in v2.0's not-yet-shipped equivalent) keyed
    /// by `reducerQualifiedName`.
    public var reducerQualifiedName: String
    public var reducerLocation: String
    public var stateTypeName: String
    public var actionTypeName: String

    /// Swift-source predicate the M4.D stub emitter will embed into
    /// the verifier as `#expect(<predicate>)` per generated action.
    /// Example: `"state.total == state.items.map(\\.price).reduce(0, +)"`
    /// for a Conservation invariant. The predicate's free variable
    /// is `state` — the closure parameter the stub binds at each
    /// step.
    public var predicate: String

    /// V1-shape score. Same 0..N+ integer scale as the v1
    /// `Suggestion.score`, fed by the §4.1 per-family signals from
    /// PRD v2.0.
    public var score: Int

    /// Effective tier. Set by the M4+ template engine per the §4.2
    /// score → tier mapping (≥75 strong, 40–74 likely, 20–39
    /// possible, <20 suppressed). PRD §3.5 corollary: every new
    /// family ships at default `.possible` visibility through three
    /// calibration cycles, so M4.B/C's scoring weights are
    /// deliberately tuned to land in the `.possible` range until
    /// promotion.
    public var tier: Tier

    /// "Why suggested" bullet points per PRD §4.5 — one per active
    /// signal that contributed to the score. Rendered in the
    /// `discover-interaction` explainability block.
    public var whySuggested: [String]

    /// "Why this might be wrong" bullet points per PRD §4.5 —
    /// active counter-signals + known limitations (e.g.
    /// floating-point round-off, action enum size, edge cases the
    /// generator might not cover).
    public var whyMightBeWrong: [String]

    /// Wall-clock time the suggestion was first emitted. ISO8601-
    /// encoded in JSON. Used by §17.2's time-to-adoption metric
    /// (decision timestamp − firstSeenAt) — same anchor v1.71 wired
    /// for algebraic suggestions via the SemanticIndex.
    public var firstSeenAt: Date

    /// M3 (multi-module measured verify) — the SwiftPM target/module the
    /// source `ReducerCandidate` was discovered in, or `nil` for a
    /// single-target run / non-reducer (view-model) carrier / older records.
    /// Copied from `ReducerCandidate.moduleName` at emission so the verify
    /// survey can build each identity against *its* module's library product
    /// (via `PackageProductResolver.libraryProduct(exposingModule:)`), rather
    /// than assuming one module for the whole run. Backward-compatible
    /// optional (missing key → `nil`).
    public var moduleName: String?

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
        firstSeenAt: Date,
        moduleName: String? = nil
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
        self.moduleName = moduleName
    }

    /// Cycle 112 — return a copy with selected fields overridden. Used by
    /// the verify-evidence fold (`InteractionVerifyEvidenceScoring`) to
    /// re-grade a suggestion — a new score / tier plus an appended
    /// explainability line — without restating every field. `nil` keeps
    /// the existing value.
    public func with(
        score: Int? = nil,
        tier: Tier? = nil,
        whySuggested: [String]? = nil,
        whyMightBeWrong: [String]? = nil
    ) -> Self {
        // **Centralising the rebuild into one `with(…)` was half the fix, and this is the other
        // half.** A single site is far better than eight — but a single site that still rebuilds
        // field-by-field still drops any field it forgets, silently, because the initialiser's
        // parameters have defaults. Mutating a copy cannot.
        var copy = self
        if let score { copy.score = score }
        if let tier { copy.tier = tier }
        if let whySuggested { copy.whySuggested = whySuggested }
        if let whyMightBeWrong { copy.whyMightBeWrong = whyMightBeWrong }
        return copy
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
    /// A `.redux`-family reducer's paradigm-distinctive purity guarantee:
    /// `reduce(s, a) == reduce(s, a)` for the same inputs. Unlike the other
    /// families this is not a State-shape predicate but a two-call
    /// comparison (mirrors `idempotence`'s post-loop double-apply), and it
    /// is genuinely falsifiable at runtime — a hidden `Date()` / `UUID()` /
    /// `.random()` makes the two calls differ, which static purity analysis
    /// cannot catch.
    case determinism
    /// A `.redux`-family reducer with an *open* Action alphabet (a protocol
    /// `Action` à la ReSwift, or String/opaque dispatch — `actionCases` is
    /// empty): an action the reducer does not recognise should fall through to
    /// the default branch and leave State unchanged — `reduce(s, unknown) ==
    /// s`. Measured by minting a fresh probe type conforming to the open
    /// alphabet and asserting the reducer leaves State untouched. Closed Swift
    /// enums are exhaustive, so no "unknown" is representable and the family
    /// never fires on them.
    case unknownActionIsNoOp = "unknown-action-is-no-op"
    /// A convention role's (VIPER interactor / MVP presenter) paradigm-
    /// distinctive guarantee: given the same input, the role's calls to its
    /// output protocol are deterministic. Unlike the other families this is
    /// neither a State-shape predicate nor a reducer property — it's verified
    /// by a dedicated harness (`OutputDeterminismVerifierEmitter`) that runs the
    /// role twice with a *recording* fake for the output collaborator and
    /// compares the recorded call logs. A hidden `Date()` / `UUID()` /
    /// `.random()` in the output path makes the two logs differ. Discovered off
    /// `ConventionRoleDiscoverer` roles, not the reducer template engine.
    case outputDeterminism = "output-determinism"
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

        case .conservation, .idempotence, .referentialIntegrity, .determinism,
             .unknownActionIsNoOp, .outputDeterminism:
            return nil
        }
    }

    /// The score → tier mapping for this family, honoring the Finding-G
    /// promotion gate (cycle 107 / cycle 112). A family carrying a
    /// `swiftProjectLintDeferral` (cardinality + biconditional) is
    /// **clamped to `.possible` regardless of score** — it detects a
    /// representable-illegal-state refactor smell, not a high-precision
    /// runtime property, so it must never promote off `.possible` even
    /// when a score signal (template scoring *or* a verify-evidence fold)
    /// would otherwise lift it.
    ///
    /// Single source of truth: both template emission
    /// (`InteractionTemplateFamily.tierFor`) and the verify-evidence
    /// re-grade (`InteractionVerifyEvidenceScoring`) route through here,
    /// so the gate can't be bypassed on one path and not the other.
    func tier(forScore score: Int) -> Tier {
        swiftProjectLintDeferral == nil ? Tier(score: score) : .possible
    }
}
