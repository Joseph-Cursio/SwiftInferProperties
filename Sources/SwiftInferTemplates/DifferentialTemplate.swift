import SwiftInferCore

/// The **differential / oracle** law: two implementations of one specification
/// must agree, for every input.
///
///     Parser.parse(source:)                            // the reference
///     Parser.parseIncrementally(source:parseTransition:)  // must match it
///
///     ⟹  parseIncrementally(source: s, parseTransition: t).tree == parse(source: s)
///
/// `docs/parsing-catalog-gap.md` §6. The family had **two independent
/// witnesses** before it was built, which is why it was built first among the
/// holes:
///
/// 1. swift-syntax states exactly this law in its own test utilities
///    (`IncrementalParseTestUtils.swift:26` — *"incrementally parsing the
///    edited source … produces the same syntax tree as reparsing the post-edit
///    file from scratch"*), quantified over every edit, and written as an
///    example harness because no framework claimed the shape.
/// 2. TestLifter cannot see `mySort(x) == x.sorted()` in a hand-rolled random
///    test, for the same reason: no template names "result equals a reference
///    computation", so no detector maps to it.
///
/// ## Why this is worth a template even though it fires rarely
///
/// Measured before building: 12 candidate pairs across ~5,900 distinct
/// function names in seven corpora. That is 0.2%, and it is the correct trade
/// rather than a disappointment — a fast path silently diverging from its
/// reference is precisely the bug an example test cannot find, because the
/// example was written against whichever path the author had in mind.
///
/// ## Scored as a conjecture, not an entailment
///
/// Base **35** for the named pair, which is `.possible` on its own and clears
/// the default cut only with corroboration. The name is strong evidence that
/// someone wrote two implementations of one thing; it is not proof they are
/// meant to be interchangeable. `naiveFoo` may be a *deliberately different*
/// algorithm kept for comparison, and a `Fallback` may be specified to differ
/// when the fast path is unavailable.
public enum DifferentialTemplate {

    public static func suggest(for pair: VariantPair) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: pair)
    }

    public static func makeConstraint() -> Constraint<VariantPair> {
        Constraint<VariantPair>(
            templateName: "differential-equivalence",
            appliesTo: { _ in true },
            signals: Self.signals(for:),
            evidence: { [$0.reference.inferenceEvidence, $0.variant.inferenceEvidence] },
            identity: { pair in
                SuggestionIdentity(
                    canonicalInput: "differential-equivalence|"
                        + "\(pair.reference.containingTypeName ?? "")|\(pair.reference.name)|"
                        + "\(pair.variant.containingTypeName ?? "")|\(pair.variant.name)"
                )
            },
            carrier: { $0.reference.containingTypeName },
            carrierType: { $0.reference.parameters.first?.typeText },
            caveats: Self.caveats(for:)
        )
    }

    static func signals(for pair: VariantPair) -> [Signal] {
        // Checked before any positive signal: a precondition-eliding variant is
        // not a second implementation, and its law cannot be executed either way
        // round. See `Signal.Kind.preconditionElidingVariant` for the measurement.
        if let veto = preconditionElidingVeto(for: pair) { return [veto] }
        var signals: [Signal] = [
            Signal(
                kind: .exactNameMatch,
                weight: 35,
                detail: "Variant-implementation name pair: `\(pair.naming.reference)` is the "
                    + "reference and `\(pair.naming.variant)` is the same computation marked "
                    + "`\(pair.naming.marker)` — two implementations of one specification owe "
                    + "agreement on every input"
            )
        ]
        signals.append(
            Signal(
                kind: .typeSymmetrySignature,
                weight: 20,
                detail: "`\(pair.variant.name)` accepts everything `\(pair.reference.name)` "
                    + "does, in the same order"
                    + (pair.variant.parameters.count > pair.reference.parameters.count
                        ? ", plus the extra state that makes the fast path fast"
                        : "")
            )
        )
        if let projection = pair.projection {
            signals.append(
                Signal(
                    kind: .typeSymmetrySignature,
                    weight: 10,
                    detail: "`\(pair.variant.name)` returns a wrapper whose `\(projection)` is "
                        + "exactly `\(pair.reference.name)`'s result — the law compares those"
                )
            )
        }
        if pair.reference.containingTypeName != pair.variant.containingTypeName {
            signals.append(
                Signal(
                    kind: .crossTypeRoundTripPair,
                    weight: -15,
                    detail: "The two halves live in different types "
                        + "(\(pair.reference.containingTypeName ?? "<top-level>") vs "
                        + "\(pair.variant.containingTypeName ?? "<top-level>")) — a variant is "
                        + "usually declared beside its reference, so this pairing is weaker "
                        + "evidence that they implement one specification"
                )
            )
        }
        return signals
    }

    /// The veto for variants that only drop a precondition — `load`/`unsafeLoad`,
    /// `append`/`uncheckedAppend`.
    ///
    /// Returned as the *sole* signal so the suppression reason is unambiguous in
    /// the calibration record: a reader asking why this pair vanished sees one
    /// line naming the marker, not a veto buried under two positive signals it
    /// overrides.
    static func preconditionElidingVeto(for pair: VariantPair) -> Signal? {
        guard pair.naming.elidesPrecondition else { return nil }
        return Signal(
            kind: .preconditionElidingVariant,
            weight: Signal.vetoWeight,
            detail: "`\(pair.naming.variant)` is `\(pair.naming.reference)` with the "
                + "`\(pair.naming.marker)` precondition dropped, not a second implementation of "
                + "it — so the differential law cannot be RUN, in either direction. Where the "
                + "precondition holds the two agree trivially (the reference is normally the "
                + "checked wrapper around the variant); where it does not, the variant traps or "
                + "is undefined, and a trap is not a refutation. Measured: this marker class has "
                + "produced zero true positives on every corpus tried, and 57 false Likely claims "
                + "on stdlib/public/core alone"
        )
    }

    static func caveats(for pair: VariantPair) -> [String] {
        var caveats = [
            "THE LAW RUNS IN ONE DIRECTION: `\(pair.naming.reference)` is the specification and "
                + "`\(pair.naming.variant)` must match it. A counterexample is a bug in "
                + "`\(pair.naming.variant)`, not a disagreement between equals — so shrink and "
                + "read it as such.",
            "THIS IS A CONJECTURE from the naming, not an entailment. Two implementations may be "
                + "kept side by side precisely BECAUSE they differ — a `Fallback` may be specified "
                + "to behave differently when the fast path is unavailable, and a `Naive` variant "
                + "may be retained as a foil rather than an oracle. Confirm they are meant to be "
                + "interchangeable before encoding this.",
            "CHECK WHETHER `\(pair.naming.reference)` simply CALLS `\(pair.naming.variant)`. If it "
                + "guards and delegates, the marked half is the COLD BRANCH of one function rather "
                + "than a second implementation of it, and the two are meant to disagree exactly "
                + "where the guard short-circuits. Measured example: swift-collections' "
                + "`_ensureFreeCapacity` returns early when capacity already suffices and "
                + "otherwise calls `_ensureFreeCapacitySlow`, which reallocates unconditionally — "
                + "so they differ on every input the guard catches, and the law would be false "
                + "for correct code."
        ]
        caveats.append(contentsOf: conditionalCaveats(for: pair))
        return caveats
    }

    /// The caveats that depend on what KIND of variant this is — split from
    /// `caveats(for:)` to stay under the function-length cap.
    static func conditionalCaveats(for pair: VariantPair) -> [String] {
        var caveats: [String] = []
        if pair.naming.elidesPrecondition {
            caveats.append(
                "`\(pair.naming.variant)` ELIDES A PRECONDITION rather than optimising a "
                    + "computation, so the law is CONDITIONAL: the two agree only on inputs "
                    + "where that precondition holds. A generator that violates it will trap "
                    + "inside `\(pair.naming.variant)`, and THAT TRAP IS NOT A REFUTATION — it is "
                    + "the function behaving as documented on an input you promised not to give "
                    + "it. Constrain the generator to the precondition, then the comparison "
                    + "means something."
            )
        }
        if pair.variant.parameters.count > pair.reference.parameters.count {
            let extra = pair.variant.parameters
                .dropFirst(pair.reference.parameters.count)
                .map { $0.label ?? $0.internalName }
                .joined(separator: ", ")
            caveats.append(
                "THE EXTRA ARGUMENT (`\(extra)`) IS WHERE THE PROPERTY LIVES. Passing a single "
                    + "fixed value — `nil`, or one recorded transition — turns this back into the "
                    + "example test it already has. The claim worth making is that the two agree "
                    + "for EVERY valid value of it, so generate that argument, and bias it toward "
                    + "the states the fast path treats specially (an empty edit, an edit at a "
                    + "boundary, an edit that invalidates everything)."
            )
        }
        if pair.projection != nil {
            caveats.append(
                "Equality is checked on the projected member only. Anything else the variant's "
                    + "result carries is outside this law — if that other state can also be "
                    + "wrong, it needs its own."
            )
        }
        return caveats
    }
}
