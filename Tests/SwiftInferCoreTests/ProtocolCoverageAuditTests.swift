@testable import SwiftInferCore
import Testing

/// **Auditing the coverage veto's premise.**
///
/// `ProtocolCoverageMap` suppresses a law when a conformance means PropertyLawKit checks it.
/// Its doc asserts *"the kit's `check<Protocol>PropertyLaws` DOES verify the property"* — a
/// claim about a package the project may not depend on, and nothing checked it. The veto is
/// unconditional while the coverage it assumes is conditional on adoption, and the failure
/// is silent: a veto that prevents double-reporting looks exactly like nothing to report.
@Suite("Coverage veto — is its premise actually true?")
struct ProtocolCoverageAuditTests {

    private let userTypes: [String: Set<String>] = [
        "Money": ["Equatable", "AdditiveArithmetic"],
        "Tag": ["Equatable"],
        "Plain": ["Sendable"]          // no coverage-bearing conformance
    ]

    private func log(_ types: [String]) -> KitEvidenceLog {
        KitEvidenceLog(outcomes: types.map {
            KitLawOutcome(typeName: $0, law: "Equatable.reflexivity", outcome: .passed, tier: .strict)
        })
    }

    // MARK: - The three states

    @Test("no kit evidence at all → assumed, not contradicted")
    func noEvidenceIsAssumed() {
        let findings = ProtocolCoverageAudit.audit(
            inheritedTypesByName: userTypes, kitEvidence: KitEvidenceLog()
        )
        #expect(findings.count == 2, "Plain has no coverage-bearing conformance")
        #expect(findings.allSatisfy { $0.standing == .assumed })
    }

    @Test("kit evidence naming the type → verified")
    func exercisedIsVerified() {
        let findings = ProtocolCoverageAudit.audit(
            inheritedTypesByName: userTypes, kitEvidence: log(["Money", "Tag"])
        )
        #expect(findings.allSatisfy { $0.standing == .verified })
    }

    /// The sharp case: the project demonstrably uses the kit and demonstrably did not run it
    /// on these types, so the veto's premise is false *for them specifically*.
    @Test("kit evidence that omits the type → contradicted")
    func unexercisedWithEvidenceIsContradicted() {
        let findings = ProtocolCoverageAudit.audit(
            inheritedTypesByName: userTypes, kitEvidence: log(["SomethingElse"])
        )
        #expect(findings.allSatisfy { $0.standing == .contradicted })
        #expect(findings.map(\.typeName) == ["Money", "Tag"], "sorted, and Plain excluded")
    }

    /// `wasExercised` alone cannot separate the last two states — it is false both when the
    /// kit never ran and when it ran elsewhere. The emptiness of the log is what tells them
    /// apart, and conflating them would report every no-kit project as contradicted.
    @Test("wasExercised alone cannot distinguish assumed from contradicted")
    func emptinessIsWhatSeparatesThem() {
        #expect(KitEvidenceLog().wasExercised("Money") == false)
        #expect(log(["Other"]).wasExercised("Money") == false)
        // Same query, opposite standings — decided by whether ANY evidence exists.
        let assumed = ProtocolCoverageAudit.audit(
            inheritedTypesByName: ["Money": ["Equatable"]], kitEvidence: KitEvidenceLog()
        )
        let contradicted = ProtocolCoverageAudit.audit(
            inheritedTypesByName: ["Money": ["Equatable"]], kitEvidence: log(["Other"])
        )
        #expect(assumed.first?.standing == .assumed)
        #expect(contradicted.first?.standing == .contradicted)
    }

    // MARK: - The stdlib bake-in

    /// **Caught by running it.** `inheritedTypesIndex` merges the curated stdlib
    /// conformances in, so a two-type file audited to 22 carriers — `Array`, `Bool`,
    /// `Dictionary` and friends. Naming those is worse than noise: the kit demonstrably DOES
    /// cover `Array`, so it is a false alarm the reader cannot act on either.
    @Test("the curated stdlib bake-in is excluded")
    func stdlibBakeInIsExcluded() {
        var index = userTypes
        index["Array"] = ["Equatable", "Collection"]
        index["Bool"] = ["Equatable"]
        let findings = ProtocolCoverageAudit.audit(
            inheritedTypesByName: index, kitEvidence: KitEvidenceLog()
        )
        #expect(findings.map(\.typeName) == ["Money", "Tag"])
    }

    // MARK: - Diagnostics

    @Test("only contradicted names carriers; assumed gets one aggregate line")
    func diagnosticsShape() {
        let contradicted = ProtocolCoverageAudit.diagnostics(
            for: ProtocolCoverageAudit.audit(
                inheritedTypesByName: userTypes, kitEvidence: log(["Other"])
            )
        )
        #expect(contradicted.count == 1)
        #expect(contradicted[0].contains("Money, Tag"))
        #expect(contradicted[0].contains("checked by nothing"))

        let assumed = ProtocolCoverageAudit.diagnostics(
            for: ProtocolCoverageAudit.audit(
                inheritedTypesByName: userTypes, kitEvidence: KitEvidenceLog()
            )
        )
        #expect(assumed.count == 1)
        #expect(assumed[0].contains("2 carrier(s)"))
        #expect(assumed[0].contains("Money") == false, "aggregate only — no per-type noise")
    }

    @Test("verified says nothing — silence is correct when the premise holds")
    func verifiedIsSilent() {
        let lines = ProtocolCoverageAudit.diagnostics(
            for: ProtocolCoverageAudit.audit(
                inheritedTypesByName: userTypes, kitEvidence: log(["Money", "Tag"])
            )
        )
        #expect(lines.isEmpty)
    }

    @Test("nothing vetoed at all → no lines")
    func noVetoesNoLines() {
        let lines = ProtocolCoverageAudit.diagnostics(
            for: ProtocolCoverageAudit.audit(
                inheritedTypesByName: ["Plain": ["Sendable"]], kitEvidence: KitEvidenceLog()
            )
        )
        #expect(lines.isEmpty)
    }
}
