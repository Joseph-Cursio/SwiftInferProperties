import Foundation
@testable import SwiftInferCLI
import Testing

/// V1.144 — the prove-then-show classifier/renderer. Groups live survey
/// records into Proven / Disproven / Unverifiable / Inconclusive, with the
/// unverifiable remainder explicitly separated from a pass.
@Suite("ProveThenShowRenderer — V1.144 test-then-surface view")
struct ProveThenShowRendererTests {

    private typealias Record = SwiftInferCommand.Verify.SurveyRecord
    private typealias Outcome = SwiftInferCommand.Verify.SurveyOutcome

    private func record(
        _ carrier: String?,
        _ template: String,
        _ function: String,
        _ outcome: Outcome,
        detail: String? = nil,
        counterexample: String? = nil
    ) -> Record {
        Record(
            identityHash: "0x\(function)\(template)",
            templateName: template,
            primaryFunctionName: function,
            carrier: carrier,
            outcome: outcome,
            outcomeDetail: detail,
            counterexample: counterexample
        )
    }

    @Test("V1.144 — empty index → guidance line")
    func emptyRecords() {
        let rendered = ProveThenShowRenderer.render([])
        #expect(rendered.contains("index is empty"))
    }

    @Test("V1.144 — the four buckets classify by outcome, with a summary tally")
    func fourBuckets() {
        let disproven = record(
            "Level", "commutativity", "combine(_:_:)", .measuredDefaultFails,
            counterexample: "combine(low, high)"
        )
        let unverifiable = record(
            "BigUInt", "commutativity", "+(a:b:)", .architecturalCoveragePending,
            detail: "unsupported-carrier: BigUInt"
        )
        let records: [Record] = [
            record("Level", "commutativity", "join(_:_:)", .measuredBothPass),
            record("Level", "associativity", "join(_:_:)", .measuredBothPass),
            disproven,
            unverifiable,
            record("Flaky", "idempotence", "wobble()", .measuredError, detail: "build-failed")
        ]
        let out = ProveThenShowRenderer.render(records)
        #expect(out.contains("Prove-then-show — 5 pick(s) tested"))
        #expect(out.contains("Proven 2 · Disproven 1 · Unverifiable 1 · Inconclusive 1"))
        // Section headers present.
        #expect(out.contains("PROVEN — surface these"))
        #expect(out.contains("DISPROVEN — drop these"))
        #expect(out.contains("UNVERIFIABLE — NOT tested, NOT a pass"))
        #expect(out.contains("INCONCLUSIVE"))
        // Rows land in the right sections.
        #expect(out.contains("✓ Level  commutativity  join(_:_:)"))
        #expect(out.contains("✗ Level  commutativity  combine(_:_:)   [counterexample: combine(low, high)]"))
        #expect(out.contains("? BigUInt  commutativity  +(a:b:)   (unsupported-carrier: BigUInt)"))
    }

    @Test("V1.144 — empty sections are omitted entirely")
    func emptySectionsOmitted() {
        // Only proven rows → no Disproven/Unverifiable/Inconclusive headers.
        let out = ProveThenShowRenderer.render([
            record("Level", "commutativity", "join(_:_:)", .measuredBothPass)
        ])
        #expect(out.contains("PROVEN"))
        #expect(!out.contains("DISPROVEN"))
        #expect(!out.contains("UNVERIFIABLE"))
        #expect(!out.contains("INCONCLUSIVE"))
    }

    @Test("V1.144 — shrunk counterexample preferred over the raw one")
    func shrunkPreferred() {
        let rec = Record(
            identityHash: "0x1", templateName: "commutativity", primaryFunctionName: "f(_:_:)",
            carrier: "T", outcome: .measuredDefaultFails,
            outcomeDetail: nil, counterexample: "big", shrunkCounterexample: "min"
        )
        let out = ProveThenShowRenderer.render([rec])
        #expect(out.contains("[counterexample: min]"))
        #expect(!out.contains("[counterexample: big]"))
    }

    @Test("V1.144 — free functions (nil carrier) render as (free)")
    func freeFunctionCarrier() {
        let out = ProveThenShowRenderer.render([
            record(nil, "monotonicity", "log(_:)", .measuredBothPass)
        ])
        #expect(out.contains("✓ (free)  monotonicity  log(_:)"))
    }
}
