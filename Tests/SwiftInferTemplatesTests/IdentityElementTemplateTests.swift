import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

// swiftlint:disable type_body_length file_length
// Test suites cohere around their subject — splitting along the 250-line
// body / 400-line file limit would scatter the identity-element template
// + pairing assertions across multiple files for no reader benefit.
@Suite("IdentityElementTemplate — pair shape, naming, empty-seed signal, vetoes")
struct IdentityElementTemplateTests {

    // MARK: - Pair construction

    @Test("Binary op + same-typed identity constant scores 70 (Likely) by construction")
    func pairScoresSeventyByConstruction() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        // 30 type + 40 identity-element naming = 70 → Likely.
        #expect(suggestion.score.total == 70)
        #expect(suggestion.score.tier == .likely)
    }

    @Test("Empty-seed signal adds 20 when the op appears in opsWithIdentitySeed")
    func emptySeedSignalPromotesToStrong() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(
            IdentityElementTemplate.suggest(for: pair, opsWithIdentitySeed: ["merge"])
        )
        // 30 + 40 + 20 = 90 → Strong.
        #expect(suggestion.score.total == 90)
        #expect(suggestion.score.tier == .strong)
        let line = suggestion.explainability.whySuggested.first { $0.contains("empty-seed") }
        #expect(line == "Accumulator-with-empty-seed: 'merge' used in .reduce(<identity-shape>, op) (+20)")
    }

    @Test("Empty-seed set without the op's name doesn't fire the signal")
    func emptySeedSignalMissWhenOpNameAbsent() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(
            IdentityElementTemplate.suggest(for: pair, opsWithIdentitySeed: ["other"])
        )
        #expect(suggestion.score.total == 70)
    }

    // MARK: - Vetoes

    @Test("Non-deterministic body in op suppresses regardless of identity match")
    func nonDeterministicVetoSuppresses() {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet",
            opBodySignals: BodySignals(
                hasNonDeterministicCall: true,
                hasSelfComposition: false,
                nonDeterministicAPIsDetected: ["UUID"]
            )
        )
        #expect(IdentityElementTemplate.suggest(for: pair) == nil)
    }

    // MARK: - Suggestion shape

    @Test("Suggestion uses the 'identity-element' template ID and carries op + identity Evidence")
    func evidenceCarriesOpAndIdentity() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.templateName == "identity-element")
        #expect(suggestion.evidence.count == 2)
        #expect(suggestion.evidence[0].displayName == "merge(_:_:)")
        #expect(suggestion.evidence[0].signature == "(IntSet, IntSet) -> IntSet")
        #expect(suggestion.evidence[1].displayName == "IntSet.empty")
        #expect(suggestion.evidence[1].signature == ": IntSet")
    }

    @Test("Generator and sampling are M2 placeholders (M3/M4 deferred)")
    func placeholderGeneratorAndSampling() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.generator.source == .notYetComputed)
        #expect(suggestion.generator.confidence == nil)
        #expect(suggestion.generator.sampling == .notRun)
    }

    @Test("Caveats include Equatable, class-equality, and the two-sided identity warning")
    func caveatsAlwaysPresent() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        #expect(suggestion.explainability.whyMightBeWrong.count == 3)
        #expect(suggestion.explainability.whyMightBeWrong[0].contains("Equatable"))
        #expect(suggestion.explainability.whyMightBeWrong[1].contains("class"))
        #expect(suggestion.explainability.whyMightBeWrong[2].contains("two-sided"))
    }

    // MARK: - Suggestion identity

    @Test("Suggestion identity is namespaced by 'identity-element' and includes op + identity key")
    func identityIncludesTemplateID() throws {
        let pair = makePair(
            opName: "merge",
            paramTypes: ("IntSet", "IntSet"),
            returnType: "IntSet",
            identityName: "empty",
            identityType: "IntSet"
        )
        let suggestion = try #require(IdentityElementTemplate.suggest(for: pair))
        let commutativityIdentity = SuggestionIdentity(
            canonicalInput: "commutativity|" + IdempotenceTemplate.canonicalSignature(of: pair.operation)
        )
        #expect(suggestion.identity != commutativityIdentity)
    }

    @Test("Same op + same identity at a different file location preserves identity hash")
    func identityIsLocationIndependent() throws {
        let opA = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "IntSet", isInout: false)
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let opB = FunctionSummary(
            name: "merge",
            parameters: opA.parameters,
            returnTypeText: opA.returnTypeText,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "B.swift", line: 99, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let identityA = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let identityB = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "C.swift", line: 50, column: 1)
        )
        let suggestionA = try #require(
            IdentityElementTemplate.suggest(for: IdentityElementPair(operation: opA, identity: identityA))
        )
        let suggestionB = try #require(
            IdentityElementTemplate.suggest(for: IdentityElementPair(operation: opB, identity: identityB))
        )
        #expect(suggestionA.identity == suggestionB.identity)
    }

    // MARK: - IdentityElementPairing — type filter

    @Test("Pairing emits one pair per (op, identity) on matching T")
    func pairingMatchesByType() {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "IntSet", isInout: false)
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let intSetEmpty = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let stringEmpty = IdentityCandidate(
            name: "empty",
            typeText: "String",
            containingTypeName: "String",
            location: SourceLocation(file: "B.swift", line: 1, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [merge],
            identities: [intSetEmpty, stringEmpty]
        )
        #expect(pairs.count == 1)
        #expect(pairs.first?.identity.typeText == "IntSet")
    }

    @Test("Pairing rejects non-binary-op summaries")
    func pairingRejectsNonBinaryOps() {
        let normalize = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "s", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 1, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        let stringEmpty = IdentityCandidate(
            name: "empty",
            typeText: "String",
            containingTypeName: "String",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [normalize],
            identities: [stringEmpty]
        )
        #expect(pairs.isEmpty)
    }

    @Test("Same op + multiple same-typed identities yields one pair per identity")
    func multipleIdentitiesYieldMultiplePairs() {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "a", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "b", typeText: "IntSet", isInout: false)
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "A.swift", line: 10, column: 1),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let zero = IdentityCandidate(
            name: "zero",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 4, column: 1)
        )
        let empty = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "A.swift", line: 5, column: 1)
        )
        let pairs = IdentityElementPairing.candidates(
            in: [merge],
            identities: [zero, empty]
        )
        #expect(pairs.count == 2)
        #expect(Set(pairs.map(\.identity.name)) == ["zero", "empty"])
    }

    // MARK: - Golden render

    @Test("Strong identity-element suggestion (op + identity + empty-seed) renders byte-for-byte")
    func strongIdentityElementGoldenRender() throws {
        let pair = makeGoldenRenderPair()
        let suggestion = try #require(
            IdentityElementTemplate.suggest(for: pair, opsWithIdentitySeed: ["merge"])
        )
        let rendered = SuggestionRenderer.render(suggestion)
        #expect(rendered == expectedGoldenRender(suggestion: suggestion))
    }

    private func makeGoldenRenderPair() -> IdentityElementPair {
        let merge = FunctionSummary(
            name: "merge",
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: "IntSet", isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: "IntSet", isInout: false)
            ],
            returnTypeText: "IntSet",
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Sources/Demo/Sets.swift", line: 12, column: 5),
            containingTypeName: "IntSet",
            bodySignals: .empty
        )
        let empty = IdentityCandidate(
            name: "empty",
            typeText: "IntSet",
            containingTypeName: "IntSet",
            location: SourceLocation(file: "Sources/Demo/Sets.swift", line: 5, column: 5)
        )
        return IdentityElementPair(operation: merge, identity: empty)
    }

    private func expectedGoldenRender(suggestion: Suggestion) -> String {
        let seedHex = SamplingSeed.renderHex(SamplingSeed.derive(from: suggestion.identity))
        return """
[Suggestion]
Template: identity-element
Score:    90 (Strong)

Why suggested:
  ✓ merge(_:_:) (IntSet, IntSet) -> IntSet — Sources/Demo/Sets.swift:12
  ✓ IntSet.empty: IntSet — Sources/Demo/Sets.swift:5
  ✓ Type-symmetry signature: (T, T) -> T with identity T.empty (T = IntSet) (+30)
  ✓ Curated identity-element constant: 'IntSet.empty' on type IntSet (+40)
  ✓ Accumulator-with-empty-seed: 'merge' used in .reduce(<identity-shape>, op) (+20)

Why this might be wrong:
  ⚠ T must conform to Equatable for the emitted property to compile. \
SwiftInfer M1 does not verify protocol conformance — confirm before applying.
  ⚠ If T is a class with a custom ==, the property is over value equality as T.== defines it.
  ⚠ The identity property is two-sided: f(t, e) == t AND f(e, t) == t. \
A one-sided identity (e.g. left-identity only) will pass the type pattern but \
fail one of the emitted assertions under M4 sampling.

Generator: not yet computed (M3 prerequisite)
Sampling:  not run; lifted test seed: \(seedHex)
Identity:  \(suggestion.identity.display)
Suppress:  // swiftinfer: skip \(suggestion.identity.display)
"""
    }

    // MARK: - Helpers

    private func makePair(
        opName: String,
        paramTypes: (String, String),
        returnType: String,
        identityName: String,
        identityType: String,
        opBodySignals: BodySignals = .empty
    ) -> IdentityElementPair {
        let operation = FunctionSummary(
            name: opName,
            parameters: [
                Parameter(label: nil, internalName: "lhs", typeText: paramTypes.0, isInout: false),
                Parameter(label: nil, internalName: "rhs", typeText: paramTypes.1, isInout: false)
            ],
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: returnType,
            bodySignals: opBodySignals
        )
        let identity = IdentityCandidate(
            name: identityName,
            typeText: identityType,
            containingTypeName: identityType,
            location: SourceLocation(file: "Test.swift", line: 5, column: 1)
        )
        return IdentityElementPair(operation: operation, identity: identity)
    }
}
// swiftlint:enable type_body_length
