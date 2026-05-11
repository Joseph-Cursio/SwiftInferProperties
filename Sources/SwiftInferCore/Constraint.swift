/// V1.36.A — Constraint Engine foundation (PRD §20.2, part 1).
///
/// A `Constraint<Subject>` describes a property pattern **as data**:
/// subject-shape gate, signal accumulator, evidence builder, identity-
/// key builder, optional carrier accessor, optional explainability
/// caveats. The `ConstraintRunner` (V1.36.B) orchestrates a Constraint
/// against a specific subject to produce a `Suggestion?`.
///
/// **Why this exists.** PRD §20.2 calls for replacing "templates as
/// patterns over signatures" with "constraints over a function graph +
/// types + usage." v1's templates are bespoke matchers — each
/// hand-rolls its type checks, signal accumulation, and Suggestion
/// construction. The Constraint abstraction lets templates express
/// themselves as data (the constraint values) consumed by a single
/// orchestrator (the runner), so:
///
///   - New properties land as Constraint values, not bespoke matcher
///     code.
///   - Higher-order property composition becomes expressible (future
///     v1.38+).
///   - The scoring engine is replaceable behind the matcher without
///     touching downstream contracts (PRD §20.2 guarantee preserved).
///
/// **Generic over Subject.** Unary templates use
/// `Constraint<FunctionSummary>`; pair templates use
/// `Constraint<FunctionPair>`; lifted templates use
/// `Constraint<LiftedTransformation>`; identity-element uses
/// `Constraint<IdentityElementPair>`; dual-style uses
/// `Constraint<DualStylePair>`. No type erasure at the data-model
/// layer — each template's Constraint type-checks against its natural
/// subject.
///
/// **Sendable closures** so a Constraint can be passed across actor
/// boundaries — future-proofing for the v1.37+ multi-template
/// registry where many constraints are evaluated in parallel.
///
/// **v1.36 ships a single migrated template** (Commutativity) as
/// proof-of-concept. The remaining 9 templates continue to use their
/// bespoke matchers in v1.36; v1.37+ migrates them incrementally with
/// per-template equivalence tests guaranteeing bit-for-bit Suggestion
/// preservation.
public struct Constraint<Subject>: Sendable {

    /// Stable template-id string (e.g. `"commutativity"`,
    /// `"round-trip"`). Used as the emitted `Suggestion.templateName`.
    public let templateName: String

    /// Subject-shape gate. Returns `true` iff the constraint applies
    /// to this subject (e.g., for commutativity:
    /// `(T, T) -> T` binary-op shape with `T = paramType`). Pure
    /// function — no side effects. When `false`, the runner returns
    /// `nil` without computing signals or building evidence.
    public let appliesTo: @Sendable (Subject) -> Bool

    /// Signal accumulator. Returns every signal the runner should
    /// score against — positive signals (type shape, name match),
    /// counter-signals (direction labels, asymmetric markers, etc.),
    /// AND veto signals. The runner detects `Signal.isVeto` via
    /// `Score(signals:)` and collapses to `.suppressed` per the
    /// canonical scoring contract.
    public let signals: @Sendable (Subject) -> [Signal]

    /// Evidence builder for the §4.5 explainability block. One entry
    /// per matched function or function-pair half. The runner threads
    /// this into the emitted `Suggestion.evidence`.
    public let evidence: @Sendable (Subject) -> [Evidence]

    /// Identity-key builder for the PRD §7.5 canonical-input hash.
    /// The constraint owns the canonical-input format — it knows
    /// which subject fields are identity-stable across refactors.
    public let identity: @Sendable (Subject) -> SuggestionIdentity

    /// Carrier-type accessor for V1.34.A's `Suggestion.carrier` field.
    /// Returns `nil` for templates whose subjects don't expose a
    /// natural carrier (free functions, etc.). The default
    /// `{ _ in nil }` lets simple templates omit this argument.
    public let carrier: @Sendable (Subject) -> String?

    /// Template-specific "why this might be wrong" caveats that aren't
    /// derivable from signals alone. The runner appends these to the
    /// ExplainabilityBlock's `whyMightBeWrong` list. Defaults to empty
    /// — templates that need caveats override this.
    public let caveats: @Sendable (Subject) -> [String]

    public init(
        templateName: String,
        appliesTo: @Sendable @escaping (Subject) -> Bool,
        signals: @Sendable @escaping (Subject) -> [Signal],
        evidence: @Sendable @escaping (Subject) -> [Evidence],
        identity: @Sendable @escaping (Subject) -> SuggestionIdentity,
        carrier: @Sendable @escaping (Subject) -> String? = { _ in nil },
        caveats: @Sendable @escaping (Subject) -> [String] = { _ in [] }
    ) {
        self.templateName = templateName
        self.appliesTo = appliesTo
        self.signals = signals
        self.evidence = evidence
        self.identity = identity
        self.carrier = carrier
        self.caveats = caveats
    }
}
