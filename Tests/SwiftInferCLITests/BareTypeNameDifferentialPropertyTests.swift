import Foundation
import PropertyLawKit
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// Self-dogfood road test, 2026-08-08 — the cross-target half of
// `NameStrippingDifferentialPropertyTests`.
//
// Nine functions in `Sources/` strip a type name. Seven are the same function:
// four spelled `strippingGenericParameters` in `SwiftInferCore` (pinned in the
// Core suite) and three spelled `bareTypeName`:
//
//   * `SwiftInferCommand.Index.bareTypeName(from:)`  (IndexCommand+Projection.swift:185)
//   * `RoundTripPairResolver.bareTypeName(from:)`    (RoundTripPairResolver.swift:136)
//   * `DoccPageBuilder.bareTypeName(_:)`             (DoccPageBuilder.swift:244)
//
// **Two more share the name and do something entirely different**, and that is
// the hazard this suite exists to pin rather than to fix:
//
//   * `OutputDeterminismVerifierEmitter.bareTypeName(_:)` strips an `any `
//     prefix and trailing `?`/`!`/space — and leaves generics alone.
//   * `SelectionSubsetTemplate.bareTypeName(_:)` strips only a trailing `?`.
//
// So `bareTypeName("Array<Int>")` is `"Array"` in three places and
// `"Array<Int>"` in two others, under one name, across three targets. Nothing
// in the suite ran two of them on one input before this file.
//
// **What is testable here is bounded by access control, and that is itself the
// road test's finding.** `DoccPageBuilder.bareTypeName` and
// `OutputDeterminismVerifierEmitter.bareTypeName` are `private`, so `@testable
// import` cannot reach them — `@testable` promotes `internal`, not `private`.
// `SelectionSubsetTemplate.bareTypeName` is `internal` to `SwiftInferTemplates`,
// which this test target does not depend on directly. The two pinned below are
// the two that are reachable; the divergent pair is documented here because a
// comment is the only instrument available for them without changing production
// access levels.
//
// The same measurement is why `discover`'s own Strong-tier picks on this target
// were unlandable: `normalize(prefix:)` and `normalize(hash:)`
// (`VerifyHarness.swift:145`/`:156`) are both `private static`, and 22 of 38
// non-`predicate` subjects it proposed for `SwiftInferCLI` are `private`.
@Suite("Road test — bareTypeName agrees with the Core strip, across targets")
struct BareTypeNameDifferentialPropertyTests {

    // MARK: - The reachable implementations
    //
    // `SwiftInferCore.CarrierKindResolver` is the reference side because it is
    // `public` and because `CarrierKind` classification keys on its answer, so a
    // CLI copy that drifted from it would mis-file an index entry rather than
    // merely render a different string.

    private static let implementations: [(name: String, strip: @Sendable (String) -> String)] = [
        ("SwiftInferCommand.Index", { SwiftInferCommand.Index.bareTypeName(from: $0) }),
        ("RoundTripPairResolver", { RoundTripPairResolver.bareTypeName(from: $0) })
    ]

    private static let reference = CarrierKindResolver.strippingGenericParameters

    // MARK: - Generator
    //
    // The same alphabet as the Core suite, so a divergence found on one side is
    // reproducible on the other with the identical input.

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

    /// **The cross-target differential law.** Both CLI copies must agree with the
    /// Core implementation on every type name.
    ///
    /// This is the law that matters most of the nine, because these two run at
    /// different pipeline stages on the *same* carrier string:
    /// `SwiftInferCommand.Index.bareTypeName` decides what
    /// `SemanticIndexEntry.typeName` records, and `RoundTripPairResolver`
    /// decides which curated stdlib entry a pair matches. Divergence would make
    /// `query --type Foo` and the round-trip anchor disagree about what the
    /// carrier is called, with no error anywhere.
    @Test("both CLI bareTypeName copies agree with the Core strip")
    func cliCopiesAgreeWithCore() async {
        await propertyCheck(input: Self.nameGen) { name in
            let expected = Self.reference(name)
            for implementation in Self.implementations {
                #expect(
                    implementation.strip(name) == expected,
                    """
                    \(implementation.name).bareTypeName disagrees with \
                    CarrierKindResolver on "\(name)": got \
                    "\(implementation.strip(name))", expected "\(expected)"
                    """
                )
            }
        }
    }

    /// **Idempotence**, stated per copy rather than inferred from the law above.
    ///
    /// Agreement with the reference plus the reference being idempotent does
    /// imply it — but only while agreement holds. Stated separately so that a
    /// future divergence produces two distinct failures (which copy drifted, and
    /// whether the drifted one is at least self-consistent) instead of one.
    @Test("both CLI copies are idempotent")
    func cliCopiesAreIdempotent() async {
        await propertyCheck(input: Self.nameGen) { name in
            for implementation in Self.implementations {
                let once = implementation.strip(name)
                #expect(
                    implementation.strip(once) == once,
                    "\(implementation.name).bareTypeName is not idempotent on \"\(name)\""
                )
            }
        }
    }

    /// **The two same-named outliers really are different**, pinned as a law so
    /// that "unify the nine `bareTypeName`s" cannot be done silently.
    ///
    /// `SelectionSubsetTemplate.bareTypeName` and
    /// `OutputDeterminismVerifierEmitter.bareTypeName` are unreachable from here
    /// (see the suite header), so this checks the *observable consequence* on the
    /// reachable side: the Core strip removes a generic argument list, which is
    /// exactly the behaviour those two lack. If someone makes them agree, this
    /// test still passes — it is a guard on the reference's meaning, not on
    /// theirs. The comment carries what the code cannot.
    @Test("the Core strip removes generic arguments — the behaviour the outliers lack")
    func referenceStripsGenericsUnlikeTheOutliers() {
        #expect(Self.reference("Array<Int>") == "Array")
        #expect(Self.reference("Optional<Int>?") == "Optional")
        // The outliers would return "Array<Int>" and "Optional<Int>" respectively.
        #expect(Self.reference("any Collection") == "any Collection")
    }
}
