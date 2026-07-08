import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.147 — the stdlib confidence anchor: proven-analog / known-trap
/// provenance for discovered candidates over standard-library carriers.
@Suite("StdlibAnchor — V1.147 proven-analog provenance")
struct StdlibAnchorTests {

    // MARK: - firstParameterType

    @Test("V1.147 — parses the first parameter type, depth-aware over generics")
    func firstParameterType() {
        #expect(StdlibAnchor.firstParameterType(from: "(Set<Int>, Set<Int>) -> Set<Int>") == "Set<Int>")
        #expect(StdlibAnchor.firstParameterType(from: "(String, String) -> String") == "String")
        #expect(StdlibAnchor.firstParameterType(from: "([Int], [Int]) -> [Int]") == "[Int]")
        #expect(StdlibAnchor.firstParameterType(from: "no parens") == nil)
    }

    // MARK: - provenance

    @Test("V1.147 — Set commutativity yields BOTH a proven analog (union) and a trap (subtracting)")
    func setCommutativityAmbiguity() {
        let (why, wrong) = StdlibAnchor.provenance(templateName: "commutativity", carrier: "Set<Int>")
        #expect(why.contains { $0.contains("a.union(b) == b.union(a)") && $0.contains("Semilattice") })
        #expect(wrong.contains { $0.contains("subtracting") })
    }

    @Test("V1.147 — String associativity is a proven Monoid analog; commutativity is a trap")
    func stringAnchors() {
        let assoc = StdlibAnchor.provenance(templateName: "associativity", carrier: "String")
        #expect(assoc.whySuggested.contains { $0.contains("Monoid") })
        #expect(assoc.whyMightBeWrong.isEmpty)

        let comm = StdlibAnchor.provenance(templateName: "commutativity", carrier: "String")
        #expect(comm.whySuggested.isEmpty)
        #expect(comm.whyMightBeWrong.contains { $0.contains("NOT commutative") })
    }

    @Test("V1.147 — a non-catalog carrier produces no provenance")
    func customCarrierIsSilent() {
        let (why, wrong) = StdlibAnchor.provenance(templateName: "commutativity", carrier: "MyDomainType")
        #expect(why.isEmpty)
        #expect(wrong.isEmpty)
    }

    // MARK: - enriched (over the evidence signature)

    private func makeSuggestion(
        templateName: String,
        signature: String,
        carrier: String?
    ) -> Suggestion {
        let evidence = Evidence(
            displayName: "combine(_:_:)",
            signature: signature,
            location: SourceLocation(file: "/x.swift", line: 1, column: 1)
        )
        return Suggestion(
            templateName: templateName,
            evidence: [evidence],
            score: Score(signals: [Signal(kind: .typeSymmetrySignature, weight: 30, detail: "shape")]),
            generator: GeneratorMetadata(source: .notYetComputed, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: ["base"], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "x"),
            carrier: carrier
        )
    }

    @Test("V1.147 — enriched pulls the operand type from the signature, not the enclosing carrier")
    func enrichedFromSignature() {
        // Mirrors a real static op: carrier is the enclosing enum, T is in the signature.
        let suggestion = makeSuggestion(
            templateName: "commutativity",
            signature: "(Set<Int>, Set<Int>) -> Set<Int>",
            carrier: "Ops"
        )
        let enriched = StdlibAnchor.enriched(suggestion)
        #expect(enriched.explainability.whySuggested.contains { $0.contains("a.union(b)") })
        #expect(enriched.explainability.whyMightBeWrong.contains { $0.contains("subtracting") })
        #expect(enriched.explainability.whySuggested.first == "base")   // original preserved, appended
    }

    @Test("V1.147 — enriched leaves a custom-carrier suggestion untouched")
    func enrichedNoOpForCustom() {
        let suggestion = makeSuggestion(
            templateName: "commutativity",
            signature: "(Widget, Widget) -> Widget",
            carrier: "Registry"
        )
        let enriched = StdlibAnchor.enriched(suggestion)
        #expect(enriched == suggestion)
    }
}
