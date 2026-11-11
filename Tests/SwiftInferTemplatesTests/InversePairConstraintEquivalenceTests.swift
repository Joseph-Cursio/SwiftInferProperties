import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// V1.40.F — equivalence tests for the v1.40 batch migration of the
/// last 5 templates (InversePair non-lifted + lifted, IdentityElement
/// non-lifted + lifted, Composition) — completing the 10-template
/// Constraint Engine refactor (PRD §20.2). Verifies that:
///   - InversePair / Composition / IdempotenceLifted-style migrations
///     produce bit-for-bit identical Suggestion via the wrapper +
///     via ConstraintRunner.
///   - IdentityElement (non-lifted + lifted) use the **wrapper
///     migration pattern** — the Constraint drives signals + evidence
///     + identity + carrier; the wrapper rebuilds Suggestion with
///     bespoke explainability to preserve the no-space identity-
///     evidence rendering.
@Suite("InversePairTemplate non-lifted — V1.40.F Constraint equivalence")
struct InversePairConstraintEquivalenceTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String,
        param: String,
        ret: String,
        container: String? = "Foo"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: [Parameter(label: nil, internalName: "x", typeText: param, isInout: false)],
            returnTypeText: ret,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: loc,
            containingTypeName: container,
            bodySignals: .empty
        )
    }

    @Test("V1.40.F — InversePair non-lifted: wrapper matches Constraint output across corpus")
    func equivalence() {
        let corpus: [(label: String, pair: FunctionPair)] = [
            ("encode_decode_userType", FunctionPair(
                forward: Self.summary(name: "encode", param: "MyType", ret: "String"),
                reverse: Self.summary(name: "decode", param: "String", ret: "MyType")
            )),
            ("transform_untransform", FunctionPair(
                forward: Self.summary(name: "transform", param: "Token", ret: "Token"),
                reverse: Self.summary(name: "untransform", param: "Token", ret: "Token")
            )),
        ]
        for (label, pair) in corpus {
            let wrapper = InversePairTemplate.suggest(for: pair)
            let runner = ConstraintRunner.suggest(
                constraint: InversePairTemplate.makeConstraint(
                    vocabulary: .empty,
                    equatableResolver: nil,
                    inheritedTypesByName: [:],
                    carrierKindResolver: nil
                ),
                subject: pair
            )
            #expect(wrapper == runner, "[\(label)] disagree")
        }
    }
}
