import SwiftInferCore

/// Inverse-pair template — `f: T -> U` paired with `g: U -> T` where
/// `T` does *not* classify as `Equatable` per `EquatableResolver`
/// (M3.3). Fills the gap RoundTripTemplate (M1.4) leaves: round-trip
/// vetoes when `T` is not Equatable since its emitted property uses
/// `==`; inverse-pair surfaces the structural claim as a Possible-tier
/// informational suggestion the user can act on with a custom equality
/// witness or annotation API extension.
///
/// Necessary type pattern (PRD §5.2 + §5.8 M8 row): the pair's
/// type shape (enforced by `FunctionPairing`) plus `T` *not*
/// classifying as `.equatable`. Equatable `T` defers to RoundTripTemplate;
/// this template only fires when the resolver returns `.notEquatable` or
/// `.unknown` for the forward param type. When no resolver is supplied
/// (test/programmatic-discovery callers that haven't threaded
/// `typeDecls` through), the template assumes "non-Equatable" so it
/// still fires — same posture as RoundTripTemplate's `vocabulary: .empty`
/// default.
///
/// Score lands in the Possible tier (20–39) per PRD §5.8's
/// "suppressed by default" posture — type-pattern alone scores 25;
/// curated naming or project-vocabulary `inversePairs` adds 10.
/// Hidden behind `--include-possible` per the §5.8 M8 row; explicit
/// `--include-possible` exposes them. The type-flow `g(f(x))`
/// composition signal (PRD §5.3 inverse-by-usage) is *not* shipped in
/// M8.1 because `BodySignals` doesn't carry an inverse-composition
/// flag yet — `hasSelfComposition` only catches `f(f(x))`. Adding the
/// flag is a small `FunctionScanner` extension; deferred to v1.1+ per
/// the M8 plan ("the type-flow `g(f(x))` composition signal ... lands
/// once `BodySignals` surface this").
public enum InversePairTemplate {

    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// the template consults `vocabulary.inversePairs` alongside the
    /// curated list shared with `RoundTripTemplate`.
    ///
    /// `equatableResolver` gates the template — `nil` defaults to "fire"
    /// so callers without corpus type-decls (tests, programmatic
    /// callers) still surface the suggestion; CLI / `discover(in:)`
    /// passes a real resolver built from the scanned `typeDecls`.
    ///
    /// V1.5.2 — `inheritedTypesByName` feeds the protocol-coverage
    /// veto. Forward type's conformance set drives the lookup;
    /// candidate properties are `additiveInverse` (covered by
    /// SignedNumeric — the kit's `checkSignedNumericPropertyLaws`
    /// verifies `a + (-a) == .zero`) + `groupInverse` (covered by kit
    /// Group — the kit's `checkGroupPropertyLaws` verifies the
    /// abstract `combine(x, x⁻¹) == .identity`). Other inverse pairs
    /// (e.g. `parse/format` on a custom Doc type) fall through
    /// unsuppressed.
    /// V1.40.A — migrated to the Constraint Engine (PRD §20.2). 4
    /// runtime inputs incl. EquatableResolver (new). Behavior preserved
    /// bit-for-bit.
    public static func suggest(
        for pair: FunctionPair,
        vocabulary: Vocabulary = .empty,
        equatableResolver: EquatableResolver? = nil,
        inheritedTypesByName: [String: Set<String>] = [:],
        carrierKindResolver: CarrierKindResolver? = nil
    ) -> Suggestion? {
        ConstraintRunner.suggest(
            constraint: makeConstraint(
                vocabulary: vocabulary,
                equatableResolver: equatableResolver,
                inheritedTypesByName: inheritedTypesByName,
                carrierKindResolver: carrierKindResolver
            ),
            subject: pair
        )
    }

    /// V1.40.A — Constraint factory.
    public static func makeConstraint(
        vocabulary: Vocabulary,
        equatableResolver: EquatableResolver?,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> Constraint<FunctionPair> {
        Constraint<FunctionPair>(
            templateName: "inverse-pair",
            appliesTo: { pair in
                Self.passesInverseGate(for: pair, equatableResolver: equatableResolver)
            },
            signals: { pair in
                Self.accumulatedSignals(
                    for: pair,
                    vocabulary: vocabulary,
                    inheritedTypesByName: inheritedTypesByName,
                    carrierKindResolver: carrierKindResolver
                )
            },
            evidence: { pair in
                [pair.forward.inferenceEvidence, pair.reverse.inferenceEvidence]
            },
            identity: Self.makeIdentity(for:),
            carrier: { $0.forward.containingTypeName },
            caveats: { pair in Self.makeCaveats(for: pair) }
        )
    }

    /// V1.40.A — gate: forward param exists AND T is NOT classified
    /// as `.equatable` (the .equatable case defers to RoundTripTemplate).
    static func passesInverseGate(
        for pair: FunctionPair,
        equatableResolver: EquatableResolver?
    ) -> Bool {
        guard let domain = pair.forward.parameters.first?.typeText else {
            return false
        }
        if let resolver = equatableResolver,
           resolver.classify(typeText: domain) == .equatable {
            return false
        }
        return true
    }

    /// V1.40.A — preserves the pre-migration signal-accumulation order.
    static func accumulatedSignals(
        for pair: FunctionPair,
        vocabulary: Vocabulary,
        inheritedTypesByName: [String: Set<String>],
        carrierKindResolver: CarrierKindResolver?
    ) -> [Signal] {
        var signals: [Signal] = [typeSymmetrySignal(for: pair)]
        signals.append(contentsOf: counterAndCoverageSignals(
            for: pair,
            vocabulary: vocabulary,
            inheritedTypesByName: inheritedTypesByName,
            carrierKindResolver: carrierKindResolver
        ))
        return signals
    }

    /// V1.40.A — caveat list (4 base + optional FP advisory).
    static func makeCaveats(for pair: FunctionPair) -> [String] {
        var caveats: [String] = [
            "Non-Equatable T means SwiftInfer cannot sample-verify the round-trip — "
                + "the suggestion is name-and-type-pattern only.",
            "TestLifter corroboration not yet wired (gated on TestLifter M1).",
            "Possible-tier by default — escalation requires a custom equality witness "
                + "or annotation API extension.",
            "If T conforms to Equatable, RoundTripTemplate (M1.4) handles this case "
                + "with stronger evidence — inverse-pair only fires when "
                + "EquatableResolver returns .notEquatable or .unknown for T.",
        ]
        if let fpCaveat = floatingPointAdvisory(for: pair) {
            caveats.append(fpCaveat)
        }
        return caveats
    }

    /// Canonical hash input per PRD §7.5: `template ID | canonical
    /// signature A | canonical signature B`, where A and B are sorted
    /// lexicographically so the hash is orientation-agnostic. Mirrors
    /// `RoundTripTemplate.makeIdentity` so the two templates produce
    /// distinct identity hashes for the same pair (different template
    /// prefix), avoiding collision in the decisions / baseline files.
    private static func makeIdentity(for pair: FunctionPair) -> SuggestionIdentity {
        let forwardSig = IdempotenceTemplate.canonicalSignature(of: pair.forward)
        let reverseSig = IdempotenceTemplate.canonicalSignature(of: pair.reverse)
        let sorted = [forwardSig, reverseSig].sorted()
        return SuggestionIdentity(canonicalInput: "inverse-pair|" + sorted.joined(separator: "|"))
    }
}
