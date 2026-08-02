/// A law IDENTIFIER — the unit `ProtocolCoverageMap` reasons about when deciding whether a
/// conformance means PropertyLawKit already covers what a template would propose.
///
/// **Split out of `ProtocolCoverageMap.swift` on 2026-08-02.** The two were deliberately
/// co-located — *"splitting them adds an import hop without adding clarity"* — but that
/// argument was always weaker than it read: both live in `SwiftInferCore`, so there is no
/// import hop, and the 2026-08-02 law-level audit took the combined file past the 400-line
/// cap. The table and the vocabulary it is keyed by now grow independently.
///
/// Not to be confused with `SwiftInferCLI.CuratedEntry`, which until 2026-07-30 was also
/// called `KnownProperty`. That one is a struct holding a curated catalog row about a stdlib
/// type; this one is an enum of identifiers. Renaming it was the fix; this note is so the
/// name does not drift back.
public enum KnownProperty: String, Sendable, Hashable, CaseIterable {

    // — Additive (stdlib AdditiveArithmetic / Numeric / SignedNumeric)
    /// `(a + b) + c == a + (b + c)`
    case additiveAssociative
    /// `a + b == b + a`
    case additiveCommutative
    /// `a + .zero == a`
    case additiveIdentityZero
    /// `a + (-a) == .zero`
    case additiveInverse

    // — Multiplicative (stdlib Numeric / SignedNumeric) —
    /// `(a * b) * c == a * (b * c)`
    case multiplicativeAssociative
    /// `a * b == b * a`
    case multiplicativeCommutative
    /// `a * 1 == a`
    case multiplicativeIdentityOne
    /// `a * a⁻¹ == 1` (not covered by Numeric — listed for symmetry
    /// with `additiveInverse`; populated by future field-shaped arms.)
    case multiplicativeInverse

    // — Numeric distributivity —
    /// `a * (b + c) == a * b + a * c`
    case distributivity

    // — Set algebra (stdlib SetAlgebra) —
    //
    // There is deliberately no `setUnionAssociative`. It was here until 2026-08-02, when a
    // law-by-law sweep found the kit ships no set-associativity law at all — so the veto
    // suppressed a true, refutable law on the grounds that `checkSetAlgebraPropertyLaws`
    // ran it, and it did not. `AssociativityTemplate` now returns no candidate for the set
    // verbs and set associativity is `discover`'s to propose. Do not re-add this without
    // first adding the law to the kit. See `docs/protocol-coverage-law-drift.md` §3.
    /// `a ∪ b == b ∪ a` — kit `SetAlgebra.unionCommutativity`
    case setUnionCommutative
    /// `a ∩ b == b ∩ a` — kit `SetAlgebra.intersectionCommutativity`.
    /// Added 2026-08-02: `CommutativityTemplate.setCombinationVerbs` has proposed this since
    /// `2463ee2` (the fix that made the `876177db` backtest catch possible) while the
    /// op-class table still knew only `union`, so it fell through to no candidate and was
    /// double-reported against the kit.
    case setIntersectionCommutative
    /// `a △ b == b △ a` — kit `SetAlgebra.symmetricDifferenceCommutativity`.
    /// Same origin and same 2026-08-02 fix as `setIntersectionCommutative`.
    case setSymmetricDifferenceCommutative
    /// `a ∪ ∅ == a` — kit `SetAlgebra.emptyIdentity`
    case setUnionEmptyIdentity
    /// `a ∪ a == a` — kit `SetAlgebra.unionIdempotence`.
    /// Added 2026-08-02 with the veto that `BinaryIdempotenceTemplate` never had.
    case setUnionIdempotent
    /// `a ∩ a == a` — kit `SetAlgebra.intersectionIdempotence`
    case setIntersectionIdempotent

    // — Equatable / Comparable / Hashable —
    /// `a == a`
    case equatableReflexive
    /// `a == b ⇒ b == a`
    case equatableSymmetric
    /// `a == b ∧ b == c ⇒ a == c`
    case equatableTransitive
    /// strict-weak-ordering laws on `<` (Swift Comparable)
    case comparableTotalOrder
    /// `a == b ⇒ a.hashValue == b.hashValue`
    case hashableConsistency

    // — Strideable —
    /// `x.advanced(by: x.distance(to: y)) == y`, run by the kit as
    /// `"Strideable.distanceRoundTrip"` (`StrideableLaws.swift:72`).
    ///
    /// Added 2026-07-30 after `KitCoverageDriftTests` found the toolchain reporting this law
    /// twice: the kit runs it for any `Strideable` conformer, and `round-trip` independently
    /// proposed `distance(to:)` × `advanced(by:)` on `BinaryInteger` — which refines
    /// `Strideable` (`Integers.swift:533`), under a `//===--- Strideable conformance ---===//`
    /// banner. Re-reporting another tool's finding teaches people the tools disagree.
    case strideableDistanceRoundTrip

    // — LosslessStringConvertible —
    /// `Value(String(describing: x)) == x`, run by the kit as
    /// `"LosslessStringConvertible.roundTrip"` (`LosslessStringConvertibleLaws.swift:40`).
    ///
    /// Added 2026-07-30, and it **corrects a verdict rather than fixing a defect.** The
    /// swift.org study twice recorded the float parse/print round-trip as blocked by
    /// `initializerPairAdmissible`'s `guard label != "init"` — once in the `roundtrip`
    /// population, once at `PrintFloat.swift.gyb:795/908` — and filed both as reach gaps with
    /// "relax the gate" as the implied fix.
    ///
    /// Relaxing it would have produced a **double-report**: the kit already runs this law for
    /// any conformer. The gate is not arbitrary either — pairing evidence for `round-trip` is
    /// name-stem overlap (`base64EncodedString` ⊃ `base64Encoded`), and an unlabelled
    /// `init?(_ description: String)` synthesizes to the bare name `"init"`, which has no stem
    /// to match. Declining is correct; the entry makes it *explicit* so a future relaxation
    /// meets a veto instead of recreating the `Strideable` defect.
    /// Once an iterator returns `nil`, every subsequent `next()` returns `nil` — the
    /// **absorbing state** an exhausted iterator must stay in.
    ///
    /// Added 2026-08-01 to make a decline explicit that was previously an accident of
    /// nobody proposing the law. The swift.org `loops` study adjudicated
    /// `test/stdlib/Strideable.swift:236` — `for _ in 0..<10 { expectNil(i.next()) }` —
    /// as `gap-with-witness`, i.e. a law we do not cover. We do:
    /// `checkIteratorProtocolPropertyLaws` runs `"IteratorProtocol.terminationStability"`
    /// and its body is that law verbatim, pulling to exhaustion and then asserting two
    /// further `next()` calls are `nil`.
    ///
    /// The entry changes no output today, because no template proposes it — the same
    /// latent state `losslessStringRoundTrip` was added in. The symptom it fixes is
    /// epistemic and it had already produced one wrong verdict: without the entry there is
    /// nothing distinguishing *"declined because the kit runs it"* from *"missed"*, and a
    /// future attempt at an absorbing-state template would meet the `Strideable`
    /// double-report defect rather than a guard.
    case iteratorTerminationStability

    case losslessStringRoundTrip

    // — Codable —
    /// `decode(encode(x)) == x`
    case codableRoundTrip

    // — Kit-shaped (PropertyLawKit Monoid / Group / Semilattice) —
    /// kit `Monoid`'s identity law on `combine`
    case monoidIdentity
    /// kit `Group`'s inverse law on `combine`
    case groupInverse
    /// kit `Semilattice`'s idempotent-`combine` law (`x ⊕ x == x`)
    case semilatticeIdempotence
}
