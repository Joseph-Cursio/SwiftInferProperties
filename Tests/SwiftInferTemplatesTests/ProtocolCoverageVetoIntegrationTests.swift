import Testing
import SwiftInferCore
@testable import SwiftInferTemplates

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
}
