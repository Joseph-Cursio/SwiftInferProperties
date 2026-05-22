import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V1.5.2 — protocol-coverage veto end-to-end integration tests.
// Per-template behavioural tests live in `ProtocolCoverageVetoTests.swift`
// (single-summary) and `ProtocolCoverageVetoPairTests.swift`
// (pair-shaped). This file verifies the index-construction helper +
// the threading through `TemplateRegistry.discover(...)`.

@Suite("ProtocolCoverageVeto — discover() integration (V1.5.2)")
struct ProtocolCoverageDiscoverIntegrationTests {

    @Test("inheritedTypesIndex(from:) folds primary + extension records cross-file")
    func indexBuildMergesAcrossFiles() {
        let primary = TypeDecl(
            name: "Money",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let sameFileExt = TypeDecl(
            name: "Money",
            kind: .extension,
            inheritedTypes: ["Hashable"],
            location: SourceLocation(file: "A.swift", line: 50, column: 1)
        )
        let crossFileExt = TypeDecl(
            name: "Money",
            kind: .extension,
            inheritedTypes: ["AdditiveArithmetic"],
            location: SourceLocation(file: "B.swift", line: 1, column: 1)
        )
        let merged = ProtocolCoverageMap.inheritedTypesIndex(
            from: [primary, sameFileExt, crossFileExt]
        )
        #expect(merged["Money"] == ["Equatable", "Hashable", "AdditiveArithmetic"])
    }

    @Test("inheritedTypesIndex strips generic parameters in the key")
    func indexStripsGenericsInKey() {
        let primary = TypeDecl(
            name: "Pair<A, B>",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [primary])
        // Generic parameters strip off the key per V1.5.2 lookup contract
        #expect(merged["Pair"] == ["Equatable"])
        #expect(merged["Pair<A, B>"] == nil)
    }

    @Test("Empty inheritance clauses don't pollute the index")
    func emptyInheritanceClausesAreSkipped() {
        let bare = TypeDecl(
            name: "Bare",
            kind: .struct,
            inheritedTypes: [],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [bare])
        #expect(merged["Bare"] == nil)
    }

    @Test("End-to-end: Numeric Money + \"+\" suggestion is suppressed via discover()")
    func discoverIntegratesVetoEndToEnd() {
        let plus = makeBinaryOp(name: "+", typeText: "Money")
        let typeDecl = TypeDecl(
            name: "Money",
            kind: .struct,
            inheritedTypes: ["Numeric"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let suggestions = TemplateRegistry.discover(
            in: [plus],
            typeDecls: [typeDecl]
        )
        // Numeric covers `+`'s commutativity AND associativity.
        let templates = Set(suggestions.map(\.templateName))
        #expect(!templates.contains("commutativity"))
        #expect(!templates.contains("associativity"))
    }

    @Test("End-to-end: user-named \"combine\" on Numeric Money is NOT suppressed")
    func discoverPreservesNonOpClassMatch() {
        let combine = makeBinaryOp(name: "combine", typeText: "Money")
        let typeDecl = TypeDecl(
            name: "Money",
            kind: .struct,
            inheritedTypes: ["Numeric"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let suggestions = TemplateRegistry.discover(
            in: [combine],
            typeDecls: [typeDecl]
        )
        // `combine` is the curated commutativity verb (+40 name) plus
        // type-symmetry (+30) → 70, Likely. Op-class fall-through
        // preserves it.
        #expect(suggestions.contains { $0.templateName == "commutativity" })
    }

    // MARK: - V1.7.1 stdlib bake-in end-to-end

    @Test("V1.7.1 — Int-typed `+` is suppressed via stdlib bake-in (no corpus typeDecls)")
    func discoverSuppressesIntPlusViaBakeIn() {
        // No corpus typeDecls — the bake-in alone should reach Int's
        // AdditiveArithmetic / Numeric conformances and suppress
        // commutativity + associativity emissions.
        let plus = makeBinaryOp(name: "+", typeText: "Int")
        let suggestions = TemplateRegistry.discover(
            in: [plus],
            typeDecls: []
        )
        let templates = Set(suggestions.map(\.templateName))
        #expect(!templates.contains("commutativity"))
        #expect(!templates.contains("associativity"))
    }

    @Test("V1.7.1 — Double-typed `*` is suppressed via stdlib bake-in")
    func discoverSuppressesDoubleMulViaBakeIn() {
        let mul = makeBinaryOp(name: "*", typeText: "Double")
        let suggestions = TemplateRegistry.discover(
            in: [mul],
            typeDecls: []
        )
        let templates = Set(suggestions.map(\.templateName))
        #expect(!templates.contains("commutativity"))
        #expect(!templates.contains("associativity"))
    }

    @Test("V1.7.1 — user-named `combine` on Int still emits (op-class fall-through)")
    func discoverPreservesUserNamedCombineOnInt() {
        // Critical false-positive guard from V1.5.2 carries forward:
        // user-named `combine` on a Numeric carrier is preserved
        // because the kit covers `+`/`*` specifically, not arbitrary
        // commutative functions on stdlib-typed carriers. The bake-in
        // doesn't change this — `Int: Numeric` only covers
        // `additive*` / `multiplicative*` op-classes.
        let combine = makeBinaryOp(name: "combine", typeText: "Int")
        let suggestions = TemplateRegistry.discover(
            in: [combine],
            typeDecls: []
        )
        // `combine` is a curated commutativity verb; op-class fall-through
        // means the bake-in doesn't suppress it.
        #expect(suggestions.contains { $0.templateName == "commutativity" })
    }

    // MARK: - V1.8.1 round-trip shape-gated veto end-to-end

    @Test("V1.8.1 — (Int) -> Int user-inverse pair on Codable Int now surfaces")
    func discoverSurfacesIntInversePairAfterShapeGate() {
        // The cycle-4 false-positive case in end-to-end form. Two
        // Int-typed user-inverse functions with paired naming should
        // now produce a round-trip Possible-tier suggestion (where
        // pre-V1.8.1 they were suppressed by V1.7.1's bake-in fanning
        // V1.5.2's unconditional Codable veto).
        let minimumCapacity = makeUnaryOp(name: "minimumCapacity", from: "Int", to: "Int")
        let scaleForCapacity = makeUnaryOp(name: "scale", from: "Int", to: "Int")
        let suggestions = TemplateRegistry.discover(
            in: [minimumCapacity, scaleForCapacity],
            typeDecls: []
        )
        // The pair should surface as a round-trip suggestion (Possible
        // tier — Score 30 from type-symmetry alone, no curated name
        // bonus).
        #expect(suggestions.contains { $0.templateName == "round-trip" })
    }

    @Test("V1.8.1 — (T) -> Data + (Data) -> T on Codable T still suppressed")
    func discoverStillSuppressesCodableEncoderDecoderShape() {
        // The genuine Codable round-trip surface — kit covers it via
        // checkCodablePropertyLaws, so it should still be suppressed.
        let encode = makeUnaryOp(name: "encode", from: "Doc", to: "Data")
        let decode = makeUnaryOp(name: "decode", from: "Data", to: "Doc")
        let typeDecl = TypeDecl(
            name: "Doc",
            kind: .struct,
            inheritedTypes: ["Codable"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let suggestions = TemplateRegistry.discover(
            in: [encode, decode],
            typeDecls: [typeDecl]
        )
        // No round-trip suggestion should appear — V1.5.2's veto still fires
        // on the encoder/decoder shape with Codable carrier.
        #expect(!suggestions.contains { $0.templateName == "round-trip" })
    }
}

// MARK: - V1.8.1 fixture helpers

private func makeUnaryOp(name: String, from inputType: String, to outputType: String) -> FunctionSummary {
    FunctionSummary(
        name: name,
        parameters: [Parameter(label: nil, internalName: "x", typeText: inputType, isInout: false)],
        returnTypeText: outputType,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: false,
        location: SourceLocation(file: "Test.swift", line: 1, column: 1),
        containingTypeName: nil,
        bodySignals: .empty
    )
}
