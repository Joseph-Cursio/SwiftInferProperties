import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

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
            ),
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
            ),
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
