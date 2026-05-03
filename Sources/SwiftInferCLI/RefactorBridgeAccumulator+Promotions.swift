import SwiftInferCore

extension RefactorBridgeAccumulator {

    /// Curated additive-op names. Match the user's source-text function
    /// name verbatim (the orchestrator extracts `combineWitness` from
    /// `Evidence.displayName` via `bareName(from:)`). Conservative
    /// list — `+`, `add`, `plus`, `sum` cover the common Swift
    /// conventions. Project-vocabulary extension is a reasonable v1.1+
    /// addition; M8.4.b.2 ships only the curated list to keep the
    /// §16 #6 reproducibility surface narrow.
    static let curatedAdditiveOpNames: Set<String> = [
        "+", "add", "plus", "sum"
    ]

    /// Curated multiplicative-op names. Same posture as
    /// `curatedAdditiveOpNames`. Excludes `concat` / `merge` which are
    /// non-commutative semigroup-shaped ops, not Ring's
    /// multiplicative-monoid shape.
    static let curatedMultiplicativeOpNames: Set<String> = [
        "*", "multiply", "times", "mul", "product"
    ]

    /// Promote the accumulated signal set to one or more
    /// `RefactorBridgeProposal`s per PRD v0.4 §5.4 + the M8.4.b.1
    /// open-decision resolutions:
    /// - **Strict-greatest within each chain branch** — Semilattice
    ///   beats CommutativeMonoid beats Monoid beats Semigroup; Group
    ///   beats Monoid beats Semigroup.
    /// - **Incomparable arms emit separately** (open decision #6) —
    ///   when both `CommutativeMonoid` and `Group` apply on the same
    ///   type, both surface as peer proposals.
    /// - **Semilattice + SetAlgebra secondary** (open decision #3) —
    ///   Semilattice claims whose binary op has a curated set-named
    ///   verb (`union`, `intersect`, `subtract`, etc.) emit a
    ///   secondary stdlib `SetAlgebra` proposal alongside.
    ///
    /// Returns `[]` when the signal set doesn't support any proposal
    /// (e.g. commutativity-only with no associativity).
    var proposals: [RefactorBridgeProposal] {
        guard hasAssociativity, let combineWitness else { return [] }
        // M8.4.b.2 — Ring detection runs first. When two binary ops on
        // the same type are both Monoid-shaped AND one has a curated
        // additive name + the other a curated multiplicative name, the
        // type's structural claim is Ring (PRD §5.4 row 5).
        if let ring = ringPromotion() {
            return [ring]
        }
        // Cover the Semilattice branch first — its signal set is a
        // superset of CommutativeMonoid + Monoid + Semigroup.
        if hasAssociativity, hasIdentityElement, hasCommutativity, hasIdempotence {
            return semilatticePromotion(combineWitness: combineWitness)
        }
        // Incomparable case — both CommutativeMonoid and Group fire.
        // Per open decision #6, emit BOTH as peer proposals. Order is
        // alphabetical-ish: CommutativeMonoid (B) then Group (B').
        if hasAssociativity, hasIdentityElement, hasCommutativity, hasInverseElement {
            return [
                makeProposal(protocolName: "CommutativeMonoid", combineWitness: combineWitness),
                makeProposal(protocolName: "Group", combineWitness: combineWitness)
            ]
        }
        // Single-arm cases — exactly one promotion fires.
        if hasAssociativity, hasIdentityElement, hasInverseElement {
            return [makeProposal(protocolName: "Group", combineWitness: combineWitness)]
        }
        if hasAssociativity, hasIdentityElement, hasCommutativity {
            return [makeProposal(protocolName: "CommutativeMonoid", combineWitness: combineWitness)]
        }
        if hasAssociativity, hasIdentityElement {
            return [makeProposal(protocolName: "Monoid", combineWitness: combineWitness)]
        }
        return [makeProposal(protocolName: "Semigroup", combineWitness: combineWitness)]
    }

    /// Detect the Ring shape — two Monoid-shaped ops on the same type,
    /// one with a curated additive name and one with a curated
    /// multiplicative name. Returns the Ring proposal targeting stdlib
    /// `Numeric` (PRD §5.4 row 5) when both are found; `nil` otherwise.
    /// M8 plan open decision #4 default `(a)` for the *claim* — fires
    /// on naming alone, no TypeShape numeric-shape gating in this
    /// milestone (the strong §4.5 caveat enumerating Numeric's full
    /// requirement set is the user's safety net; v1.1+ can add the gate).
    ///
    /// **Distributivity isn't sample-verified** — we trust the curated
    /// additive/multiplicative naming as a structural hint that
    /// distributivity is intended. The §4.5 caveat flags this so the
    /// user knows the law isn't checked at suggestion time.
    private func ringPromotion() -> RefactorBridgeProposal? {
        let monoidShapedOps = perOp.filter {
            $0.value.hasAssociativity && $0.value.hasIdentity
        }
        let additive = monoidShapedOps.keys
            .filter { Self.curatedAdditiveOpNames.contains($0) }
            .sorted()
            .first
        let multiplicative = monoidShapedOps.keys
            .filter { Self.curatedMultiplicativeOpNames.contains($0) }
            .sorted()
            .first
        guard let additive, let multiplicative else { return nil }
        let additiveIdentity = monoidShapedOps[additive]?.identityName
        let multiplicativeIdentity = monoidShapedOps[multiplicative]?.identityName
        return RefactorBridgeProposal(
            typeName: typeName,
            protocolName: "Numeric",
            combineWitness: additive,
            identityWitness: additiveIdentity,
            inverseWitness: nil,
            explainability: ringExplainability(
                additiveOp: additive,
                multiplicativeOp: multiplicative,
                additiveIdentity: additiveIdentity,
                multiplicativeIdentity: multiplicativeIdentity
            ),
            relatedIdentities: identities
        )
    }

    /// §4.5 explainability for the Ring claim — lists both contributing
    /// ops + identities + a strong caveat enumerating stdlib Numeric's
    /// full requirement set the two-monoid signals don't on their own
    /// provide.
    private func ringExplainability(
        additiveOp: String,
        multiplicativeOp: String,
        additiveIdentity: String?,
        multiplicativeIdentity: String?
    ) -> ExplainabilityBlock {
        var why: [String] = ["RefactorBridge claim: \(typeName) → Ring (stdlib Numeric)"]
        why.append(
            "additive op: \(additiveOp)(_:_:) "
            + "with identity \(additiveIdentity ?? "<unknown>")"
        )
        why.append(
            "multiplicative op: \(multiplicativeOp)(_:_:) "
            + "with identity \(multiplicativeIdentity ?? "<unknown>")"
        )
        for suggestion in contributing {
            why.append("from \(suggestion.templateName): \(suggestion.evidence.first?.displayName ?? "<unknown>")")
        }
        let caveats: [String] = [
            "Both ops must satisfy associativity AND identity Strict laws "
            + "for the kit-side per-op promotions; SwiftInfer's signal accumulation "
            + "treats the union of per-op evidence as the Ring claim.",
            "Distributivity (`a * (b + c) == a*b + a*c`) is NOT sample-verified — "
            + "the curated additive/multiplicative naming is a structural hint, "
            + "not a proof. Apply the conformance only if distributivity holds.",
            "stdlib `Numeric` requires more than the two-monoid signals provide — "
            + "`Numeric.init?(exactly:)`, `Magnitude` associated type, "
            + "`Numeric.*=` / `Numeric.+=` mutating operators, `Numeric.-` (subtraction). "
            + "Apply the conformance only if your type already implements the full "
            + "Numeric surface; otherwise the extension fails to compile.",
            "**FloatingPoint caveat**: integer-like exact-equality laws "
            + "(`combineAssociativity`, distributivity) hold for `Int` but NOT "
            + "for IEEE-754 floats — rounding noise causes spurious violations. "
            + "Don't conform `Double` / `Float` / `BinaryFloatingPoint` types via "
            + "this writeout; use kit v1.4's `FloatingPoint` law check instead."
        ]
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: caveats)
    }

    /// Build a Semilattice proposal plus the SetAlgebra secondary when
    /// the binary op's name is in the curated set-shaped verb list. Per
    /// open decision #3 default `(a)`, both surface at the prompt as
    /// `[A/B/B'/s/n/?]`; user picks either.
    private func semilatticePromotion(combineWitness: String) -> [RefactorBridgeProposal] {
        let primary = makeProposal(
            protocolName: "Semilattice",
            combineWitness: combineWitness
        )
        guard isCuratedSetAlgebraOp(combineWitness) else {
            return [primary]
        }
        // SetAlgebra (stdlib) — reuses the same explainability +
        // contributing-suggestion identities as the primary Semilattice
        // claim. The §4.5 caveats list which SetAlgebra requirements
        // aren't covered by the per-template signals, pointing the user
        // at what they need to fill in manually.
        let secondary = RefactorBridgeProposal(
            typeName: typeName,
            protocolName: "SetAlgebra",
            combineWitness: combineWitness,
            identityWitness: nil,
            inverseWitness: nil,
            explainability: aggregatedExplainability(protocolName: "SetAlgebra"),
            relatedIdentities: identities
        )
        return [primary, secondary]
    }

    /// Curated binary-op names that signal a set-algebra-shaped type.
    /// Conservative list — only union / intersect / subtract shapes
    /// (and their `form`-prefixed mutating peers, which don't get
    /// classified here but the verbs cover the same semantic concept).
    /// Semilattice claims with one of these names earn the SetAlgebra
    /// secondary; other Semilattice shapes (e.g. integer max, boolean
    /// OR) skip it.
    private func isCuratedSetAlgebraOp(_ name: String) -> Bool {
        let curated: Set<String> = [
            "union",
            "intersect",
            "intersection",
            "subtract",
            "subtracting",
            "formUnion",
            "formIntersection",
            "formSymmetricDifference",
            "symmetricDifference"
        ]
        return curated.contains(name)
    }

    /// Helper to construct a proposal with all witnesses + the
    /// per-protocol caveats threaded in.
    private func makeProposal(
        protocolName: String,
        combineWitness: String
    ) -> RefactorBridgeProposal {
        RefactorBridgeProposal(
            typeName: typeName,
            protocolName: protocolName,
            combineWitness: combineWitness,
            identityWitness: needsIdentityWitness(for: protocolName) ? identityWitness : nil,
            inverseWitness: protocolName == "Group" ? inverseWitness : nil,
            explainability: aggregatedExplainability(protocolName: protocolName),
            relatedIdentities: identities
        )
    }

    /// Every kit-defined arm except Semigroup needs an identity witness.
    /// M8.4.a's CommutativeMonoid / Group / Semilattice all extend
    /// `Monoid: Semigroup` with `static var identity`.
    private func needsIdentityWitness(for protocolName: String) -> Bool {
        protocolName != "Semigroup"
    }

    private func aggregatedExplainability(protocolName: String) -> ExplainabilityBlock {
        var why: [String] = ["RefactorBridge claim: \(typeName) → \(protocolName)"]
        for suggestion in contributing {
            why.append("from \(suggestion.templateName): \(suggestion.evidence.first?.displayName ?? "<unknown>")")
        }
        if hasInverseElement, let inverseWitness, protocolName == "Group" {
            why.append("from inverse-element pairing: \(inverseWitness)(_:) -> \(typeName)")
        }
        let caveats = perProtocolCaveats(for: protocolName)
        return ExplainabilityBlock(whySuggested: why, whyMightBeWrong: caveats)
    }

    private func perProtocolCaveats(for protocolName: String) -> [String] {
        var caveats: [String] = [
            "User-supplied combine witness must satisfy associativity.",
            "SwiftInfer does not run the law — applying the conformance lets "
                + "`swift package protolawcheck` verify it on every CI run."
        ]
        switch protocolName {
        case "CommutativeMonoid":
            caveats.append(
                "Commutativity is a Strict law per kit v1.9.0 — "
                + "`combine(a, b) == combine(b, a)` must hold for every (a, b)."
            )
        case "Group":
            caveats.append(
                "Inverse witness must satisfy `combine(x, inverse(x)) == .identity` "
                + "AND `combine(inverse(x), x) == .identity` — both Strict laws "
                + "per kit v1.9.0."
            )
        case "Semilattice":
            caveats.append(
                "Idempotence is a Strict law per kit v1.9.0 — "
                + "`combine(a, a) == a` must hold for every a. Bounded join-semilattices "
                + "(set union, integer max) and bounded meet-semilattices (set "
                + "intersection, integer min) share this conformance."
            )
        case "SetAlgebra":
            caveats.append(
                "stdlib `SetAlgebra` requires more than the bounded-join-semilattice "
                + "signals on their own provide — `insert`, `remove`, `contains`, "
                + "`isSubset(of:)`, `isStrictSubset(of:)`, `isSuperset(of:)`, "
                + "`isStrictSuperset(of:)`, `isDisjoint(with:)` are not implied by "
                + "the Semilattice claim. The user must fill these in or drop the "
                + "conformance. Surfaced as a secondary Option B alongside "
                + "Semilattice (PRD §5.4 row 2's primary-kit + secondary-stdlib pattern)."
            )
        default:
            break
        }
        return caveats
    }
}
