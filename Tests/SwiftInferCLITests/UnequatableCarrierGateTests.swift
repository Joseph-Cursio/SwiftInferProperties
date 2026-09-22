import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// **A law comparing results with `==` cannot be written over a carrier with no `==`.**
///
/// The exhibit is real: `DagreLayoutEngine.fallbackLayout(_ graph: LayoutGraph) -> LayoutGraph` on
/// `SwiftUMLStudio`, whose `idempotence` stub failed with `referencing operator function '==' on
/// 'Equatable' requires that 'LayoutGraph' conform to 'Equatable'`. `carrierNotEquatable` has
/// existed in the VERIFY path all along; the accept path, which writes the stub, had no equivalent.
@Suite("Unequatable carriers — withdrawn, not emitted")
struct UnequatableCarrierGateTests {

    private func suggestion(template: String, carrier: String) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: "fallbackLayout(_:)",
                    signature: "(\(carrier)) -> \(carrier)",
                    location: SourceLocation(file: "DagreLayoutEngine.swift", line: 120, column: 5),
                    parameterTypeNames: [carrier],
                    qualifiedTypeName: "DagreLayoutEngine"
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "\(template)|\(carrier)"),
            carrier: "DagreLayoutEngine"
        )
    }

    @Test("a scanned carrier with no Equatable conformance is withdrawn")
    func unequatableIsWithdrawn() throws {
        let reason = try #require(UnequatableCarrierGate.declineReason(
            for: suggestion(template: "idempotence", carrier: "LayoutGraph"),
            scannedTypeNames: ["LayoutGraph"],
            inheritedTypesByName: ["LayoutGraph": ["Sendable"]]
        ))
        #expect(reason.contains("LayoutGraph"))
        #expect(reason.contains("Equatable"))
    }

    /// **The gate must cost no laws.** A declared conformance is untouched, directly or through a
    /// protocol that refines `Equatable`.
    @Test("a carrier that reaches Equatable is not gated")
    func equatableIsUntouched() {
        for clause in ["Equatable", "Hashable", "Comparable"] {
            #expect(UnequatableCarrierGate.declineReason(
                for: suggestion(template: "idempotence", carrier: "LayoutGraph"),
                scannedTypeNames: ["LayoutGraph"],
                inheritedTypesByName: ["LayoutGraph": [clause]]
            ) == nil, "\(clause) refines Equatable")
        }
    }

    /// ⚠ **A type the scan never saw is left alone** — *not in the index* is not *not Equatable*,
    /// which is `EquatableResolver`'s `.unknown` posture and the reason it could not carry this.
    @Test("an unscanned carrier is left alone")
    func unscannedIsLeftAlone() {
        #expect(UnequatableCarrierGate.declineReason(
            for: suggestion(template: "idempotence", carrier: "CGRect"),
            scannedTypeNames: ["LayoutGraph"],
            inheritedTypesByName: [:]
        ) == nil)
    }

    /// ⚠ **An arm comparing something other than the carrier must not be gated on it.**
    /// `predicate` returns `Bool` whatever it takes.
    @Test("an arm that does not compare the carrier is exempt")
    func nonComparingArmIsExempt() {
        #expect(UnequatableCarrierGate.declineReason(
            for: suggestion(template: "predicate", carrier: "LayoutGraph"),
            scannedTypeNames: ["LayoutGraph"],
            inheritedTypesByName: ["LayoutGraph": ["Sendable"]]
        ) == nil)
    }

    /// The conformance may be declared in an extension anywhere, so the walk steps through
    /// scanned names rather than stopping at the declaration.
    @Test("a conformance reached through another scanned type counts")
    func transitiveConformanceCounts() {
        #expect(UnequatableCarrierGate.declineReason(
            for: suggestion(template: "idempotence", carrier: "LayoutGraph"),
            scannedTypeNames: ["LayoutGraph", "GraphProtocol"],
            inheritedTypesByName: ["LayoutGraph": ["GraphProtocol"], "GraphProtocol": ["Hashable"]]
        ) == nil)
    }
}
