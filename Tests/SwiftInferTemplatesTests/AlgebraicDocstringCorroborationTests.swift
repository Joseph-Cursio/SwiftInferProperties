import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Corroborate-only docstring signal (+15) across the binary + projection
/// templates. For commutativity/associativity a documented assertion also counts
/// as the corroboration the unsupported-shape counter demands, so a documented
/// op on a bare `(T,T)->T` shape surfaces instead of being suppressed.
@Suite("Docstring corroboration — commutativity / associativity / monotonicity / round-trip")
struct AlgebraicDocstringCorroborationTests {

    // MARK: - Commutativity

    @Test("A documented commutative op on a non-curated name surfaces at 45 (Likely)")
    func documentedCommutativitySurfaces() throws {
        let summary = makeCommutativitySummary(
            name: "fuse",
            paramTypes: ("Color", "Color"),
            returnType: "Color",
            docComment: "Blends two colors. The operation is commutative."
        )
        let suggestion = try #require(CommutativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("The same op WITHOUT the docstring is suppressed as shape-only (B24)")
    func undocumentedCommutativitySuppressed() {
        let summary = makeCommutativitySummary(
            name: "fuse",
            paramTypes: ("Color", "Color"),
            returnType: "Color"
        )
        // shape 30 - 20 (unsupported-shape) = 10 -> suppressed -> nil.
        #expect(CommutativityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Associativity

    @Test("A documented associative op on a non-curated name surfaces at 45 (Likely)")
    func documentedAssociativitySurfaces() throws {
        let summary = makeCommutativitySummary(
            name: "fuse",
            paramTypes: ("Layer", "Layer"),
            returnType: "Layer",
            docComment: "Stacks two layers; this combine is associative."
        )
        let suggestion = try #require(AssociativityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 45)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("The same op WITHOUT the docstring is suppressed as shape-only")
    func undocumentedAssociativitySuppressed() {
        let summary = makeCommutativitySummary(
            name: "fuse",
            paramTypes: ("Layer", "Layer"),
            returnType: "Layer"
        )
        #expect(AssociativityTemplate.suggest(for: summary) == nil)
    }

    // MARK: - Monotonicity (Possible-by-default -> Likely)

    @Test("A documented monotone projection lifts Possible 25 -> Likely 40")
    func documentedMonotonicitySurfaces() throws {
        let summary = makeCommutativitySummary(
            name: "estimate",
            parameters: [Parameter(label: nil, internalName: "item", typeText: "Item", isInout: false)],
            returnType: "Int"
        ).withDoc("A monotone cost estimate — non-decreasing in the item size.")
        let suggestion = try #require(MonotonicityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 40)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("The same projection without the docstring stays Possible 25")
    func undocumentedMonotonicityStaysPossible() throws {
        let summary = makeCommutativitySummary(
            name: "estimate",
            parameters: [Parameter(label: nil, internalName: "item", typeText: "Item", isInout: false)],
            returnType: "Int"
        )
        let suggestion = try #require(MonotonicityTemplate.suggest(for: summary))
        #expect(suggestion.score.total == 25)
        #expect(suggestion.score.tier == .possible)
    }

    // MARK: - Round-trip (free-function pair)

    @Test("A documented free-function round-trip pair is boosted +15")
    func documentedRoundTripBoosted() throws {
        let forward = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "Widget", isInout: false)],
            returnTypeText: "Blob",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil, bodySignals: .empty,
            docComment: "Serializes a widget. `decode(encode(x))` recovers the original."
        )
        let reverse = FunctionSummary(
            name: "decode",
            parameters: [Parameter(label: nil, internalName: "blob", typeText: "Blob", isInout: false)],
            returnTypeText: "Widget",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 5, column: 1),
            containingTypeName: nil, bodySignals: .empty
        )
        let documented = try #require(RoundTripTemplate.suggest(for: FunctionPair(forward: forward, reverse: reverse)))
        let why = documented.explainability.whySuggested.joined(separator: "\n")
        #expect(why.contains("Docstring corroborates round-trip"))

        // Counterfactual: the same pair with no docstring scores 15 lower.
        let plainForward = FunctionSummary(
            name: "encode",
            parameters: [Parameter(label: nil, internalName: "value", typeText: "Widget", isInout: false)],
            returnTypeText: "Blob",
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Codec.swift", line: 1, column: 1),
            containingTypeName: nil, bodySignals: .empty
        )
        let plain = try #require(RoundTripTemplate.suggest(for: FunctionPair(forward: plainForward, reverse: reverse)))
        #expect(documented.score.total == plain.score.total + 15)
    }
}

private extension FunctionSummary {
    /// Copy with a docstring attached — keeps the monotonicity tests terse.
    func withDoc(_ doc: String) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals,
            docComment: doc
        )
    }
}
