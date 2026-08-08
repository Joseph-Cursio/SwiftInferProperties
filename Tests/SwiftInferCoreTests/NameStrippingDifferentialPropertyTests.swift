import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import Testing

// Self-dogfood road test, 2026-08-08 — and this suite exists because of what
// `swift-infer discover` did **not** say.
//
// `DifferentialTemplate` is the tool's own "two implementations of one
// specification must agree" family. Pointed at this repo it proposed
// `differential-equivalence` rows from lifted *test bodies* only, and zero from
// source — while `Sources/` declares the same generic-parameter strip **four
// times**, verbatim:
//
//   * `CarrierKindResolver.strippingGenericParameters(_:)`      (:224)
//   * `OrderSensitiveCarrierNames.strippingGenericParameters(_:)` (:64)
//   * `FloatingPointStorageNames.strippingGenericParameters(_:)`  (:92)
//   * `ProtocolCoverageMap.strippingGenericParameters(_:)`        (:302)
//
// plus five more spelled `bareTypeName` across `SwiftInferCLI` and
// `SwiftInferTemplates` (pinned from the CLI side in
// `BareTypeNameDifferentialPropertyTests`).
//
// **Why the template could not see them.** `VariantMarkers` pairs on a *name
// marker* — the variant must be spelled `parseIncrementally`, `appendUnchecked`,
// `fooSlow`. Real duplication in this codebase is spelled with the **same name
// in a different type**, which carries no marker, so the gate reaches none of
// it. That is the same failure mode `CLAUDE.md` §10 records for `homomorphism`
// ("built for a shape the language does not use"), and `VariantMarkers`' own
// measured-reach note — *12 pairs across ~5,900 function names in seven
// corpora* — lists **this repo** among the seven. The measurement was taken;
// the shape was never in scope for it.
//
// **What was already tested, and why it was not enough.** All four have
// example-based tests (`CarrierKindResolverTests:384`,
// `FloatingPointStorageNamesTests:41-45`, …). Every one of them checks the same
// four hand-picked inputs — `Complex<Double>`, `Array<Int>`, `Foo`, `""` — against
// its own implementation. Four copies of one example set cannot detect that the
// copies have drifted, because no test ever runs two of them on one input.
// These laws do.
@Suite("Road test — the four generic-parameter strips agree, and are idempotent")
struct NameStrippingDifferentialPropertyTests {

    // MARK: - The implementations under test
    //
    // Held as a labelled list rather than compared pairwise inline so a failure
    // names *which* pair diverged. A fifth copy added to `Sources/` should be
    // added here; that is the maintenance cost of the duplication, and making it
    // visible is part of the point.

    private static let implementations: [(name: String, strip: @Sendable (String) -> String)] = [
        ("CarrierKindResolver", CarrierKindResolver.strippingGenericParameters),
        ("OrderSensitiveCarrierNames", OrderSensitiveCarrierNames.strippingGenericParameters),
        ("FloatingPointStorageNames", FloatingPointStorageNames.strippingGenericParameters),
        ("ProtocolCoverageMap", ProtocolCoverageMap.strippingGenericParameters)
    ]

    /// The reference side of the differential law. Arbitrary among four claimed
    /// equals — which is exactly why the law is worth stating.
    private static let reference = CarrierKindResolver.strippingGenericParameters

    // MARK: - Generator
    //
    // Type-name shapes drawn from what the index actually holds, widened at the
    // edges these functions are most likely to disagree on: no angle bracket at
    // all, an angle bracket in first position, nested generics, a trailing `?`
    // after the closing bracket, and `any P` existentials. The empty string is in
    // the alphabet deliberately — it is the one input every example test already
    // covers, so leaving it out would make the property strictly weaker than the
    // tests it is meant to strengthen.

    private static let baseNames = [
        "Complex", "Array", "Set", "OrderedSet", "Foo", "", "T", "any Collection"
    ]

    private static let shapes = [
        "%@",
        "%@<Double>",
        "%@<Int, String>",
        "%@<Array<Int>>",
        "%@<Double>?",
        "%@?",
        "<%@>",
        "%@<",
        "%@<>",
        "%@ <Double>"
    ]

    private static let nameGen = zip(
        Gen.element(of: shapes).map { $0! },
        Gen.element(of: baseNames).map { $0! }
    ).map { shape, name in shape.replacingOccurrences(of: "%@", with: name) }

    // MARK: - Laws

    /// **The differential law — the reason this suite exists.**
    ///
    /// Four implementations of one specification must agree on every input. A
    /// divergence here is a real defect regardless of which side is "right":
    /// `ProtocolCoverageMap` keys its coverage veto on the stripped name and
    /// `CarrierKindResolver` keys carrier classification on it, so two answers to
    /// `strippingGenericParameters("Foo<Bar>")` means a carrier that is vetoed
    /// under one spelling and proposed under the other.
    @Test("all four generic-parameter strips agree on every type name")
    func allImplementationsAgree() async {
        await propertyCheck(input: Self.nameGen) { name in
            let expected = Self.reference(name)
            for implementation in Self.implementations {
                #expect(
                    implementation.strip(name) == expected,
                    """
                    \(implementation.name) disagrees with CarrierKindResolver on \
                    "\(name)": got "\(implementation.strip(name))", expected "\(expected)"
                    """
                )
            }
        }
    }

    /// **Idempotence.** Stripping an already-stripped name must be a no-op.
    ///
    /// `discover` proposed this one (Strong, 75) against
    /// `CarrierKindResolver.strippingGenericParameters` and it holds — but it
    /// holds for a reason worth pinning: the output contains no `<`, so the
    /// second call takes the `guard` early-return. An implementation that
    /// stripped from the *last* `<` instead of the first would still be
    /// idempotent, which is why the law below is stated as well.
    @Test("stripping twice equals stripping once")
    func strippingIsIdempotent() async {
        await propertyCheck(input: Self.nameGen) { name in
            for implementation in Self.implementations {
                let once = implementation.strip(name)
                #expect(
                    implementation.strip(once) == once,
                    "\(implementation.name) is not idempotent on \"\(name)\""
                )
            }
        }
    }

    /// **The postcondition.** The result carries no generic parameter list.
    ///
    /// Idempotence alone does not give this: a function that returned its input
    /// unchanged is idempotent and strips nothing. Stated separately so the pair
    /// bounds the function from both sides.
    @Test("no angle bracket survives stripping")
    func strippedNameHasNoAngleBracket() async {
        await propertyCheck(input: Self.nameGen) { name in
            for implementation in Self.implementations {
                #expect(
                    !implementation.strip(name).contains("<"),
                    "\(implementation.name) left a '<' in \"\(implementation.strip(name))\""
                )
            }
        }
    }

    /// **The result is a prefix of the input.** This is what makes the function a
    /// *strip* rather than a rewrite — it may only remove a suffix, never rename.
    ///
    /// Without it, an implementation that mapped every generic type to some
    /// canonical constant would satisfy both laws above.
    @Test("the stripped name is a prefix of the original")
    func strippedNameIsAPrefix() async {
        await propertyCheck(input: Self.nameGen) { name in
            for implementation in Self.implementations {
                #expect(
                    name.hasPrefix(implementation.strip(name)),
                    "\(implementation.name) returned a non-prefix for \"\(name)\""
                )
            }
        }
    }

    /// **Fixed point.** A name with no generic parameter list is returned
    /// untouched — the tool must not mangle `Int`, `Foo`, or `""`.
    @Test("a name with no angle bracket is returned unchanged")
    func namesWithoutGenericsAreUntouched() async {
        await propertyCheck(input: Gen.element(of: Self.baseNames).map { $0! }) { name in
            guard !name.contains("<") else { return }
            for implementation in Self.implementations {
                #expect(
                    implementation.strip(name) == name,
                    "\(implementation.name) altered the generic-free name \"\(name)\""
                )
            }
        }
    }
}
