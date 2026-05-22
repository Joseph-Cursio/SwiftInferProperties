@testable import SwiftInferCore
import Testing

/// V1.32.A — `TemplatePack` enum + pack-to-templates resolver. Per-pack
/// membership tests + cross-pack overlap assertions + `resolve` union
/// semantics + comma-separated parser edge cases.
@Suite("TemplatePack — V1.32.A domain packs")
struct TemplatePackTests {

    // MARK: - Per-pack membership

    @Test("numeric pack contains commutativity, associativity, identity-element, monotonicity")
    func numericPackMembership() {
        let names = TemplatePack.numeric.templateNames
        #expect(names == ["commutativity", "associativity", "identity-element", "monotonicity"])
    }

    @Test("serialization pack contains round-trip + inverse-pair")
    func serializationPackMembership() {
        let names = TemplatePack.serialization.templateNames
        #expect(names == ["round-trip", "inverse-pair"])
    }

    @Test("collections pack contains idempotence, monotonicity, dual-style, composition, invariant-preservation")
    func collectionsPackMembership() {
        let names = TemplatePack.collections.templateNames
        #expect(names == [
            "idempotence",
            "monotonicity",
            "dual-style-consistency",
            "composition",
            "invariant-preservation"
        ])
    }

    @Test("algebraic pack contains commutativity, associativity, identity-element, idempotence, composition")
    func algebraicPackMembership() {
        let names = TemplatePack.algebraic.templateNames
        #expect(names == [
            "commutativity",
            "associativity",
            "identity-element",
            "idempotence",
            "composition"
        ])
    }

    @Test("concurrency pack is empty (aspirational per PRD §20.3)")
    func concurrencyPackEmpty() {
        #expect(TemplatePack.concurrency.templateNames.isEmpty)
    }

    // MARK: - Cross-pack overlap

    @Test("monotonicity is in both numeric and collections (cross-pack)")
    func monotonicityCrossPack() {
        #expect(TemplatePack.numeric.templateNames.contains("monotonicity"))
        #expect(TemplatePack.collections.templateNames.contains("monotonicity"))
    }

    @Test("commutativity is in both numeric and algebraic")
    func commutativityCrossPack() {
        #expect(TemplatePack.numeric.templateNames.contains("commutativity"))
        #expect(TemplatePack.algebraic.templateNames.contains("commutativity"))
    }

    @Test("idempotence is in both collections and algebraic")
    func idempotenceCrossPack() {
        #expect(TemplatePack.collections.templateNames.contains("idempotence"))
        #expect(TemplatePack.algebraic.templateNames.contains("idempotence"))
    }

    @Test("composition is in both collections and algebraic")
    func compositionCrossPack() {
        #expect(TemplatePack.collections.templateNames.contains("composition"))
        #expect(TemplatePack.algebraic.templateNames.contains("composition"))
    }

    // MARK: - resolve union semantics

    @Test("resolve(numeric + serialization) is the union")
    func resolveUnionTwoPacks() {
        let resolved = TemplatePack.resolve([.numeric, .serialization])
        // numeric (4) + serialization (2) = 6 distinct
        #expect(resolved.count == 6)
        #expect(resolved.contains("commutativity"))
        #expect(resolved.contains("round-trip"))
    }

    @Test("resolve(numeric + algebraic) deduplicates overlapping templates")
    func resolveUnionDeduplicates() {
        let resolved = TemplatePack.resolve([.numeric, .algebraic])
        // numeric ∪ algebraic = {commutativity, associativity, identity-element,
        // monotonicity, idempotence, composition} = 6 distinct
        #expect(resolved.count == 6)
    }

    @Test("resolve(empty) is empty")
    func resolveEmptyIsEmpty() {
        #expect(TemplatePack.resolve([]).isEmpty)
    }

    @Test("resolve(all packs) covers every shipped template name")
    func resolveAllPacksCoversShipped() {
        let resolved = TemplatePack.allTemplateNames
        // The 10 currently shipped templates per the surface-counts trajectory
        let shippedTemplates: Set<String> = [
            "round-trip",
            "idempotence",
            "monotonicity",
            "commutativity",
            "associativity",
            "inverse-pair",
            "identity-element",
            "dual-style-consistency",
            "composition",
            "invariant-preservation"
        ]
        #expect(resolved == shippedTemplates)
    }

    // MARK: - Comma-separated parser

    @Test("parse('numeric,serialization') returns both packs")
    func parseTwoValid() {
        let parsed = TemplatePack.parse("numeric,serialization")
        #expect(parsed == [.numeric, .serialization])
    }

    @Test("parse with whitespace trims correctly")
    func parseTrimsWhitespace() {
        let parsed = TemplatePack.parse(" numeric , serialization ")
        #expect(parsed == [.numeric, .serialization])
    }

    @Test("parse drops unknown pack names silently")
    func parseDropsUnknown() {
        let parsed = TemplatePack.parse("numeric,bogus,serialization")
        #expect(parsed == [.numeric, .serialization])
    }

    @Test("parse('') is empty")
    func parseEmpty() {
        #expect(TemplatePack.parse("").isEmpty)
    }

    @Test("parse handles single pack")
    func parseSingle() {
        #expect(TemplatePack.parse("algebraic") == [.algebraic])
    }

    @Test("parse all 5 pack names returns full set")
    func parseAll() {
        let parsed = TemplatePack.parse("numeric,serialization,collections,algebraic,concurrency")
        #expect(parsed == Set(TemplatePack.allCases))
    }

    // MARK: - unknownPackNames

    @Test("unknownPackNames returns names that don't resolve")
    func unknownPackNamesReturnsInvalid() {
        let unknown = TemplatePack.unknownPackNames(in: "numeric,bogus,xyz,serialization")
        #expect(unknown == ["bogus", "xyz"])
    }

    @Test("unknownPackNames empty when all valid")
    func unknownPackNamesEmptyWhenValid() {
        #expect(TemplatePack.unknownPackNames(in: "numeric,collections").isEmpty)
    }
}
