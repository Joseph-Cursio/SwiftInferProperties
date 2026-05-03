import ProtoLawCore
import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

@Suite("GeneratorSelection — Codable round-trip fallback acceptance (M5.4)")
struct CodableRoundTripFallbackAcceptanceTests {

    /// Per-shape (i): `T: Codable` produces a `.derivedCodableRoundTrip`
    /// + `.medium` survivor.
    @Test
    func codableTypeYieldsDerivedCodableRoundTripMedium() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Money")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(name: "Money", inheritedTypes: ["Codable"])
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Money"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedCodableRoundTrip)
        #expect(lifted.generator.confidence == .medium)
        #expect(lifted.generator.sampling == .notRun)
        #expect(lifted.identity == suggestion.identity)
        #expect(lifted.score == suggestion.score)
        #expect(lifted.evidence == suggestion.evidence)
    }

    /// Per-shape (ii): `T: Encodable, Decodable` (separate conformances).
    @Test
    func encodableAndDecodableSeparatelyAlsoFires() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Document")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(
                name: "Document",
                inheritedTypes: ["Encodable", "Decodable"]
            )
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Document"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedCodableRoundTrip)
        #expect(lifted.generator.confidence == .medium)
    }

    /// Per-shape (ii) variant: union across primary + extension decls
    /// matches the M3 plan OD #2 mergeable-multimap shape.
    @Test
    func encodableOnPrimaryDecodableOnExtensionAlsoFires() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Mixed")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(name: "Mixed", inheritedTypes: ["Encodable"]),
            CodableFallbackTestHelper.makeTypeDecl(
                name: "Mixed",
                kind: .extension,
                inheritedTypes: ["Decodable"],
                line: 20
            )
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Mixed"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedCodableRoundTrip)
    }

    /// Per-shape (iii): `T: Equatable` (no Codable in the union) doesn't fire.
    @Test
    func equatableOnlyTypeDoesNotFire() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Plain")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(
                name: "Plain",
                inheritedTypes: ["Equatable", "Hashable"]
            )
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Plain"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .notYetComputed)
    }

    /// Per-shape (iv): `.derivedMemberwise` survivor is preserved even
    /// when the type also conforms to Codable.
    @Test
    func strategistDerivedMemberwiseIsNotOverwritten() throws {
        let placeholder = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Money")
        let memberwiseSuggestion = CodableFallbackTestHelper.rebuilding(
            placeholder,
            withSource: .derivedMemberwise,
            confidence: .medium
        )
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(
                name: "Money",
                inheritedTypes: ["Codable", "Hashable"]
            )
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [memberwiseSuggestion],
            generatorTypeByIdentity: [memberwiseSuggestion.identity: "Money"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedMemberwise)
        #expect(lifted.generator.confidence == .medium)
    }

    /// Per-shape (iv) variant: `.derivedCaseIterable`, `.derivedRawRepresentable`,
    /// and `.registered` are preserved like `.derivedMemberwise`.
    @Test
    func otherStrategistSourcesAlsoPreserved() throws {
        let placeholder = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Suit")
        let preservedSources: [GeneratorMetadata.Source] = [
            .derivedCaseIterable,
            .derivedRawRepresentable,
            .registered
        ]
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(
                name: "Suit",
                kind: .enum,
                inheritedTypes: ["Codable", "CaseIterable"]
            )
        ]
        for source in preservedSources {
            let suggestion = CodableFallbackTestHelper.rebuilding(
                placeholder,
                withSource: source,
                confidence: .high
            )
            let result = GeneratorSelection.applyCodableRoundTripFallback(
                to: [suggestion],
                generatorTypeByIdentity: [suggestion.identity: "Suit"],
                typeDecls: typeDecls
            )
            let lifted = try #require(result.first)
            #expect(lifted.generator.source == source)
        }
    }

    /// Per-shape (v): `.inferredFromTests` survivor is preserved — the
    /// M4 mock fallback ran first and its result stands.
    @Test
    func mockInferredIsNotOverwritten() throws {
        let placeholder = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Doc")
        let mockInferred = CodableFallbackTestHelper.rebuilding(
            placeholder,
            withSource: .inferredFromTests,
            confidence: .low
        )
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(name: "Doc", inheritedTypes: ["Codable"])
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [mockInferred],
            generatorTypeByIdentity: [mockInferred.identity: "Doc"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .inferredFromTests)
        #expect(lifted.generator.confidence == .low)
    }

    /// Per-shape (vi): `.notYetComputed` + `T: Codable` lands at
    /// `.derivedCodableRoundTrip` + `.medium`. Mirrors (i) but kept as
    /// the explicit acceptance-bar row.
    @Test
    func notYetComputedSurvivorWithCodableLandsAtDerivedCodableRoundTripMedium() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "Order")
        #expect(suggestion.generator.source == .notYetComputed)
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(name: "Order", inheritedTypes: ["Codable"])
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Order"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .derivedCodableRoundTrip)
        #expect(lifted.generator.confidence == .medium)
    }
}

@Suite("GeneratorSelection — Codable round-trip fallback edges (M5.4)")
struct CodableRoundTripFallbackEdgeTests {

    @Test
    func emptyTypeDeclsIsAFastPath() {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion()
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "Money"],
            typeDecls: []
        )
        #expect(result == [suggestion])
    }

    @Test
    func emptyGeneratorTypeMapIsAFastPath() {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion()
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(name: "Money", inheritedTypes: ["Codable"])
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [:],
            typeDecls: typeDecls
        )
        #expect(result == [suggestion])
    }

    @Test
    func suggestionForUnmappedTypeIsLeftUnchanged() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "MysteryType")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(name: "Money", inheritedTypes: ["Codable"])
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "MysteryType"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .notYetComputed)
    }

    @Test
    func encodableAloneDoesNotFire() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "OnlyEncodable")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(
                name: "OnlyEncodable",
                inheritedTypes: ["Encodable"]
            )
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "OnlyEncodable"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .notYetComputed)
    }

    @Test
    func decodableAloneDoesNotFire() throws {
        let suggestion = CodableFallbackTestHelper.makePlaceholderSuggestion(typeText: "OnlyDecodable")
        let typeDecls = [
            CodableFallbackTestHelper.makeTypeDecl(
                name: "OnlyDecodable",
                inheritedTypes: ["Decodable"]
            )
        ]
        let result = GeneratorSelection.applyCodableRoundTripFallback(
            to: [suggestion],
            generatorTypeByIdentity: [suggestion.identity: "OnlyDecodable"],
            typeDecls: typeDecls
        )
        let lifted = try #require(result.first)
        #expect(lifted.generator.source == .notYetComputed)
    }
}

/// Shared fixture builders for both Codable round-trip fallback suites.
enum CodableFallbackTestHelper {

    static func makePlaceholderSuggestion(
        typeText: String = "Widget",
        line: Int = 1
    ) -> Suggestion {
        let summary = FunctionSummary(
            name: "normalize",
            parameters: [
                Parameter(label: nil, internalName: "v", typeText: typeText, isInout: false)
            ],
            returnTypeText: typeText,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: false,
            location: SourceLocation(file: "Test.swift", line: line, column: 1),
            containingTypeName: nil,
            bodySignals: .empty
        )
        guard let suggestion = IdempotenceTemplate.suggest(for: summary) else {
            fatalError(
                "IdempotenceTemplate must produce a suggestion for the synthetic"
                + " (\(typeText)) -> \(typeText) shape."
            )
        }
        return suggestion
    }

    static func makeTypeDecl(
        name: String,
        kind: TypeDecl.Kind = .struct,
        inheritedTypes: [String],
        line: Int = 1
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inheritedTypes,
            location: SourceLocation(file: "\(name).swift", line: line, column: 1)
        )
    }

    static func rebuilding(
        _ suggestion: Suggestion,
        withSource source: GeneratorMetadata.Source,
        confidence: GeneratorMetadata.Confidence?
    ) -> Suggestion {
        let metadata = GeneratorMetadata(
            source: source,
            confidence: confidence,
            sampling: suggestion.generator.sampling
        )
        return Suggestion(
            templateName: suggestion.templateName,
            evidence: suggestion.evidence,
            score: suggestion.score,
            generator: metadata,
            explainability: suggestion.explainability,
            identity: suggestion.identity,
            liftedOrigin: suggestion.liftedOrigin,
            mockGenerator: suggestion.mockGenerator
        )
    }
}
