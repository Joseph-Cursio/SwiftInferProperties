import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Result-builder plumbing is vetoed from every template —
/// `docs/parsing-catalog-gap.md` §8.
///
/// Every `@resultBuilder` method has the shape `(Component) -> Component`, so
/// type-symmetry pairing turns one builder into a clique. Measured on
/// swift-syntax's `SwiftSyntaxBuilder`: **21 of 23 suggestions** came from one
/// file, `ListBuilder.swift` — 8 round-trip, 8 inverse-pair, 5 idempotence.
///
/// The idempotence rows were not false, which is worse than if they had been:
/// `buildEither(first component: Component) -> Component { component }` is the
/// identity, so its law holds by construction and no implementation could fail
/// it. Appendix C's rule is to score refutability, not suggestion count.
@Suite("Result-builder methods are vetoed from pairing and idempotence")
struct ResultBuilderVetoTests {

    private func builderMethod(
        _ name: String,
        label: String? = nil,
        param: String = "Component",
        returns: String = "Component",
        carrier: String = "ListBuilder"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [
                Parameter(label: label, internalName: "component", typeText: param, isInout: false)
            ],
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "ListBuilder.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - The closed set

    @Test("the curated set is the compiler's, complete")
    func curatedSetIsComplete() {
        // SE-0289 plus SE-0348's `buildPartialBlock`. This is not a heuristic
        // list — the compiler calls exactly these and nothing else.
        for name in [
            "buildBlock", "buildOptional", "buildEither", "buildArray",
            "buildExpression", "buildFinalResult", "buildLimitedAvailability",
            "buildPartialBlock"
        ] {
            #expect(ResultBuilderMethods.isBuilderMethod(name), "expected \(name) curated")
        }
    }

    @Test("matched exactly, never by a `build` prefix")
    func prefixMatchingIsNotUsed() {
        // Ordinary functions that merely start with `build` may own real laws;
        // a prefix test would silently suppress all of them.
        for name in [
            "buildRequest", "buildURL", "buildIndex", "buildTree",
            "build", "rebuildBlock", "buildBlockingQueue"
        ] {
            #expect(!ResultBuilderMethods.isBuilderMethod(name), "expected \(name) NOT curated")
        }
    }

    // MARK: - Pairing

    @Test("the two arms of an if/else are no longer proposed as inverses")
    func buildEitherArmsDoNotPair() {
        // The purest noise in the measurement: `buildEither(first:)` and
        // `buildEither(second:)` proposed as a round-trip AND an inverse-pair.
        let pairs = FunctionPairing.candidates(in: [
            builderMethod("buildEither", label: "first"),
            builderMethod("buildEither", label: "second")
        ])
        #expect(pairs.isEmpty)
    }

    @Test("no builder method pairs with any other, in either direction")
    func builderCliqueIsGone() {
        let clique = [
            builderMethod("buildBlock"),
            builderMethod("buildEither", label: "first"),
            builderMethod("buildEither", label: "second"),
            builderMethod("buildLimitedAvailability"),
            builderMethod("buildExpression"),
            builderMethod("buildFinalResult", returns: "FinalResult")
        ]
        #expect(FunctionPairing.candidates(in: clique).isEmpty)
        // And a builder must not pair with an ordinary function either.
        let ordinary = builderMethod("normalize", carrier: "Util")
        #expect(FunctionPairing.candidates(in: clique + [ordinary]).isEmpty)
    }

    @Test("ordinary same-shaped functions still pair — the control")
    func ordinaryPairingUnaffected() {
        let encode = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "v", typeText: "Doc", isInout: false)],
            returnTypeText: "String",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Codec", bodySignals: .empty
        )
        let decode = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "s", typeText: "String", isInout: false)],
            returnTypeText: "Doc",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 2, column: 1),
            containingTypeName: "Codec", bodySignals: .empty
        )
        #expect(FunctionPairing.candidates(in: [encode, decode]).count == 1)
    }

    // MARK: - Idempotence

    @Test("the unrefutable idempotence rows are suppressed")
    func builderIdempotenceSuppressed() throws {
        for name in ["buildBlock", "buildEither", "buildLimitedAvailability", "buildOptional"] {
            let subject = builderMethod(name)
            let veto = try #require(
                IdempotenceTemplate.resultBuilderVeto(for: subject),
                "expected a veto for \(name)"
            )
            #expect(veto.isVeto)
            #expect(veto.detail.contains("@resultBuilder"))
            #expect(IdempotenceTemplate.suggest(for: subject) == nil)
        }
    }

    @Test("a genuinely idempotent function on any carrier still surfaces")
    func trueIdempotenceSurvives() {
        // The two SwiftSyntaxBuilder survivors are of this shape — the veto had
        // to leave them alone, and did: 23 suggestions became 2, both real.
        let normalize = builderMethod("normalize", param: "Doc", returns: "Doc", carrier: "Util")
        #expect(IdempotenceTemplate.resultBuilderVeto(for: normalize) == nil)
        #expect(IdempotenceTemplate.suggest(for: normalize) != nil)
    }

    // MARK: - Why the name and not the attribute

    @Test("the veto does not depend on the carrier carrying @resultBuilder")
    func vetoIsCarrierAgnostic() {
        // The measured reason this is name-based: swift-syntax declares
        // `public protocol ListBuilder { … }` with NO `@resultBuilder`
        // attribute — it goes on the conforming types elsewhere, while the
        // methods and their defaults live on the bare protocol. An attribute
        // gate would have reached none of the 21 rows.
        for carrier in ["ListBuilder", "SomeUnannotatedProtocol", "ViewBuilder"] {
            #expect(
                IdempotenceTemplate.resultBuilderVeto(
                    for: builderMethod("buildBlock", carrier: carrier)
                )?.isVeto == true,
                "expected the veto on \(carrier) regardless of attributes"
            )
        }
    }
}
