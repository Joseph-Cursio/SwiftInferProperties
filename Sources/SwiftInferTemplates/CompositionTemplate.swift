import SwiftInferCore

/// V1.19.C — composition template for additive-monoid mutating actions.
/// For `mutating func op(by: X)` where `X` is in the curated additive-
/// monoid set, asserts that two sequential `op` calls equal one `op`
/// with the combined argument:
///
/// ```swift
/// var stepAB = original
/// stepAB.<op>(by: a)
/// stepAB.<op>(by: b)
///
/// var combined = original
/// combined.<op>(by: a + b)
///
/// stepAB == combined
/// ```
///
/// This is conversation `_3_Mutating API to Property Tests.md` step 3.2's
/// "increments compose additively" property — `incremented(incremented(c,
/// a), b) == incremented(c, a + b)` — generalized to the additive-monoid
/// curated set per the v1.19 plan §2 deliverable 2c.
///
/// **Numeric-only for v1.19** per the v1.18 plan open decision #3 lean
/// (carried forward at v1.19 plan open decision #3). Generic-monoid
/// extension (any `T` where the project corpus also has a `combine` or
/// `+` op identifying `T` as monoidal) is a v1.21+ candidate.
///
/// **Score baseline:** 30 type-shape + 40 canonical naming + 5 value-
/// semantic carrier (admission gate guaranteed) + 10 lifted-from-mutation
/// = **85 → Strong** by construction on the canonical accumulate-style
/// mutating methods (`Counter.increment(by:)`, `Tally.add(_:)`, etc.).
public enum CompositionTemplate {

    /// Curated additive-monoid type set per the v1.19 plan open decision
    /// #3 (numeric-only for v1.19). Names matched post-generic-stripping
    /// via `CarrierKindResolver.strippingGenericParameters`. The set
    /// covers stdlib `AdditiveArithmetic` conformers + Foundation
    /// `Decimal` + modern `Duration`. `Measurement` is intentionally
    /// excluded — its addition is unit-aware and the canonical
    /// composition law `op(op(s, a), b) == op(s, a + b)` only holds
    /// for matched-unit `Measurement` values, which the textual gate
    /// can't enforce. Project extension via `Vocabulary.compositionVerbs`
    /// affects naming only, not the type-shape gate.
    public static let curatedAdditiveTypes: Set<String> = [
        "Int", "Int8", "Int16", "Int32", "Int64",
        "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
        "Float", "Float16", "Float32", "Float64", "Float80",
        "Double", "CGFloat",
        "Decimal",
        "Duration"
    ]

    /// Curated additive-action verb list per the v1.19 plan open decision
    /// #4. Bias is toward algebraic-additive intent (`increment`,
    /// `accumulate`, `accrue`); `pop` / `withdraw` are deliberately
    /// excluded — their semantics on signed amounts are ambiguous and
    /// triage rubrics typically classify them as noise. Project
    /// extension via `Vocabulary.compositionVerbs` adds names without
    /// removing curated entries.
    public static let curatedVerbs: Set<String> = [
        "increment", "decrement",
        "add", "subtract",
        "accumulate", "accrue",
        "advance", "step",
        "extend", "expand",
        "shift", "offset",
        "bump", "grow", "augment",
        "append", "deposit"
    ]

    /// V1.21.B / **V1.29.C** — first-parameter labels that signal
    /// **monotone-bounded** rather than additive semantics. Direct
    /// cycle-17 finding closure (1/1 reject on
    /// `BucketIterator.advance(until: Int)`): the composition property
    /// `op(s, a).op(s, b) == op(s, a + b)` requires the parameter to
    /// contribute additively, but a label like `until:` signals
    /// "advance state up to a target" — `op(s, a).op(s, b)` produces
    /// `max(a, b)`-bounded state, not `a + b`-additive state.
    ///
    /// **V1.29.C promotes the counter to a full veto.** Cycles 17 + 20 +
    /// 23 + 25 all measured REJECT on `advance(until:)` (4-cycle stable
    /// 0% accept rate). The cycle-17 plan §"Open decisions" #2 anticipated
    /// this promotion if false-negative rate stayed at 0/N on broader
    /// corpora; cycle-25 confirms it. Veto magnitude: `Signal.vetoWeight`
    /// (previously `-25` → net 60 Likely).
    ///
    /// **Why these labels:** all signal "advance / move state up to a
    /// target", not "add a quantity additively." `by:` is deliberately
    /// excluded — `advance(by: n)` IS additive. The exclusion list is
    /// conservative; future cycles may extend (e.g., `forSteps:` in
    /// stepper-builder DSLs).
    public static let monotoneBoundedLabels: Set<String> = [
        "until",
        "to",
        "at",
        "upTo",
        "before",
        "through"
    ]

    /// V1.40.E — migrated to the Constraint Engine (PRD §20.2).
    /// Uses `additionalWhySuggested` to insert `lifted.rationale`
    /// between evidence and signal lines.
    public static func suggest(
        forLifted lifted: LiftedTransformation,
        vocabulary: Vocabulary = .empty,
        carrierKindResolver: CarrierKindResolver
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(
                vocabulary: vocabulary,
                carrierKindResolver: carrierKindResolver
            ),
            subject: lifted
        )
    }

    /// V1.40.E — Constraint factory.
    public static func makeConstraint(
        vocabulary: Vocabulary,
        carrierKindResolver: CarrierKindResolver
    ) -> Constraint<LiftedTransformation> {
        Constraint<LiftedTransformation>(
            templateName: "composition",
            appliesTo: { lifted in
                Self.typeShapeSignal(for: lifted) != nil
                    && Self.nameSignal(for: lifted, vocabulary: vocabulary) != nil
            },
            signals: { lifted in
                Self.accumulatedSignals(
                    for: lifted,
                    vocabulary: vocabulary,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { lifted in [Self.makeEvidence(lifted)] },
            identity: Self.makeIdentity(for:),
            carrier: { $0.carrier },
            caveats: { _ in Self.makeCaveats() },
            additionalWhySuggested: { [$0.rationale] }
        )
    }

    /// V1.40.E — preserves the pre-migration signal-accumulation order.
    /// The gate guarantees `typeShape` and `nameSignal` are non-nil.
    static func accumulatedSignals(
        for lifted: LiftedTransformation,
        vocabulary: Vocabulary,
        carrierKindResolver: CarrierKindResolver
    ) -> [Signal] {
        guard let typeShape = typeShapeSignal(for: lifted),
              let nameSignal = nameSignal(for: lifted, vocabulary: vocabulary) else {
            return []
        }
        var signals: [Signal] = [typeShape, nameSignal]
        if let carrier = carrierKindResolver.carrierKindSignal(
            forContainingTypeName: lifted.carrier
        ) {
            signals.append(carrier)
        }
        signals.append(liftedFromMutationSignal(for: lifted))
        if let monotoneBounded = monotoneBoundedLabelSignal(for: lifted) {
            signals.append(monotoneBounded)
        }
        if let veto = lifted.originalSummary.nonDeterministicVetoSignal {
            signals.append(veto)
        }
        return signals
    }

    /// V1.40.E — caveat list (2 constant entries).
    static func makeCaveats() -> [String] {
        [
            "X must conform to AdditiveArithmetic for `a + b` in the property "
                + "body to compile. Curated set is restricted to stdlib "
                + "AdditiveArithmetic conformers + Decimal + Duration.",
            "Property holds iff the mutating method's effect is exactly "
                + "additive on the parameter — i.e. `op(s, a + b)` is "
                + "semantically equivalent to `op(op(s, a), b)`. A method "
                + "named `increment` that clamps at a maximum or "
                + "non-linearly transforms its argument will fail at "
                + "sampling time."
        ]
    }

    // MARK: - Signals

    /// Lifted shape `(T, X) -> T` where `X` is in `curatedAdditiveTypes`.
    /// Disqualifies anything else: no-param mutators (handled by
    /// IdempotenceTemplate's no-param case), param-matches-carrier
    /// mutators (handled by IdempotenceTemplate's x-curried case),
    /// multi-param mutators, inout params.
    private static func typeShapeSignal(for lifted: LiftedTransformation) -> Signal? {
        let originalParams = lifted.originalSummary.parameters
        guard originalParams.count == 1,
              let param = originalParams.first,
              !param.isInout,
              param.typeText != lifted.carrier else {
            return nil
        }
        let stripped = CarrierKindResolver.strippingGenericParameters(param.typeText)
        guard curatedAdditiveTypes.contains(stripped) else {
            return nil
        }
        return Signal(
            kind: .typeSymmetrySignature,
            weight: 30,
            detail: "Composition shape: lifted (\(lifted.carrier), \(param.typeText)) "
                + "-> \(lifted.carrier) with X in curated additive-monoid set"
        )
    }

    private static func nameSignal(
        for lifted: LiftedTransformation,
        vocabulary: Vocabulary
    ) -> Signal? {
        let name = lifted.originalSummary.name
        if curatedVerbs.contains(name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Curated additive-action verb: '\(name)'"
            )
        }
        if vocabulary.compositionVerbs.contains(name) {
            return Signal(
                kind: .exactNameMatch,
                weight: 40,
                detail: "Project-vocabulary additive-action verb: '\(name)'"
            )
        }
        return nil
    }

    private static func liftedFromMutationSignal(
        for lifted: LiftedTransformation
    ) -> Signal {
        let labels = lifted.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        return Signal(
            kind: .liftedFromMutation,
            weight: 10,
            detail: "Lifted from `mutating func \(lifted.carrier).\(lifted.originalSummary.name)(\(labels))`"
        )
    }

    /// V1.21.B / **V1.29.C** — fires when the first non-self parameter's
    /// label is in `monotoneBoundedLabels`. V1.21.B introduced a `-25`
    /// counter-signal demoting Strong → Likely. V1.29.C promotes to a
    /// full `Signal.vetoWeight` veto per the cycle-25 4-cycle-stable-
    /// reject finding on `advance(until:)` (cycles 17 + 20 + 23 + 25).
    /// Returns `nil` for non-monotone-bounded labels (including `nil`
    /// label and `by:`).
    ///
    /// The lift's `liftedParameters[0]` is always the implicit-self
    /// binding (per `LiftedTransformation.lift`); the user-facing first
    /// parameter is `originalSummary.parameters[0]`. The composition
    /// shape gate already enforces `originalParams.count == 1`, so we
    /// safely read `[0]`.
    private static func monotoneBoundedLabelSignal(
        for lifted: LiftedTransformation
    ) -> Signal? {
        guard let firstParam = lifted.originalSummary.parameters.first,
              let label = firstParam.label,
              monotoneBoundedLabels.contains(label) else {
            return nil
        }
        return Signal(
            kind: .directionLabel,
            weight: Signal.vetoWeight,
            detail: "Monotone-bounded parameter label '\(label)' — "
                + "`op(s, a).op(s, b) = max(a, b)`-bounded state, not "
                + "additive composition `op(s, a + b)`"
        )
    }

    // MARK: - Identity + evidence

    private static func makeIdentity(for lifted: LiftedTransformation) -> SuggestionIdentity {
        SuggestionIdentity(
            canonicalInput: "composition|" + IdempotenceTemplate.canonicalSignature(of: lifted.originalSummary)
        )
    }

    private static func makeEvidence(_ lifted: LiftedTransformation) -> Evidence {
        let labels = lifted.originalSummary.parameters
            .map { ($0.label ?? "_") + ":" }
            .joined()
        let displayName = "\(lifted.carrier).\(lifted.originalSummary.name)(\(labels))"
        let paramTypes = lifted.originalSummary.parameters.map(\.typeText).joined(separator: ", ")
        let signature = "mutating (\(paramTypes)) -> Void  // composition: op(op(s, a), b) == op(s, a + b)"
        return Evidence(
            displayName: displayName,
            signature: signature,
            location: lifted.originalSummary.location
        )
    }

    private static func makeExplainability(
        for lifted: LiftedTransformation,
        signals: [Signal]
    ) -> ExplainabilityBlock {
        var whySuggested: [String] = []
        let evidence = makeEvidence(lifted)
        whySuggested.append(
            "\(evidence.displayName) \(evidence.signature) — "
                + "\(evidence.location.file):\(evidence.location.line)"
        )
        whySuggested.append(lifted.rationale)
        for signal in signals {
            whySuggested.append(signal.formattedLine)
        }
        let caveats: [String] = [
            "X must conform to AdditiveArithmetic for `a + b` in the property "
                + "body to compile. Curated set is restricted to stdlib "
                + "AdditiveArithmetic conformers + Decimal + Duration.",
            "Property holds iff the mutating method's effect is exactly "
                + "additive on the parameter — i.e. `op(s, a + b)` is "
                + "semantically equivalent to `op(op(s, a), b)`. A method "
                + "named `increment` that clamps at a maximum or "
                + "non-linearly transforms its argument will fail at "
                + "sampling time."
        ]
        return ExplainabilityBlock(whySuggested: whySuggested, whyMightBeWrong: caveats)
    }
}
