import Foundation
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// **A survey stream must carry the tier, so it can be read without its index.**
///
/// `fixtures/whole-corpus-survey/README.md` named this gap in its own tooling row —
/// *"the stream carries no tier, so it must be joined in from the index the run was taken
/// against"* — which is why `tier_split.py` needed a second input.
///
/// ## The join is what made the ratio easy to get wrong
///
/// On 2026-08-19 the whole-corpus re-take was first reported as *"178 of 538 execute, down
/// from 139 of 281"*. **266 of those 538 are `Advisory`, which cannot execute a law by
/// construction** — `Tier.advisory` is *"an informational tier for stand-alone advisory
/// findings that don't carry a runnable property"* — and the earlier index held none. The
/// honest comparison is 178 of 272 against 139 of 279: an **increase**, 50% → 65%.
///
/// Computing that required the index the run was taken against, and that index had already
/// been overwritten twice the same day. **A stream that carries its own tier cannot be
/// paired with the wrong index**, which is the whole point of the field.
@Suite("Survey records carry the tier they were indexed at")
struct SurveyRecordTierTests {

    static func entry(tier: String) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xFEEDFACE",
            templateName: "idempotence",
            typeName: "Carrier",
            score: 30,
            tier: tier,
            primaryFunctionName: "normalize(_:)",
            location: "F.swift:1",
            firstSeenAt: "2026-08-19T00:00:00Z",
            lastSeenAt: "2026-08-19T00:00:00Z"
        )
    }

    @Test("the record context carries the entry's tier")
    func contextCarriesTier() {
        let context = SwiftInferCommand.Verify.recordContext(for: Self.entry(tier: "Advisory"))
        #expect(context.tier == "Advisory")
    }

    /// **A decline is where it matters most.** Every `Advisory` row declines, so a record
    /// that dropped the tier on the decline path would lose it on exactly the population
    /// the denominator turns on.
    @Test("a declined record still carries the tier")
    func declinedRecordCarriesTier() {
        let record = SwiftInferCommand.Verify.surveyErrorRecord(
            SwiftInferCommand.Verify.recordContext(for: Self.entry(tier: "Advisory")),
            .architecturalCoveragePending,
            "not-a-candidate: no test can name the subject"
        )
        #expect(record.tier == "Advisory")
    }

    /// The field must survive the JSON round trip — the stream is the artifact, and a tier
    /// that exists only in memory helps nobody reading a frozen `.jsonl`.
    @Test("the tier survives encoding to the stream")
    func tierSurvivesEncoding() throws {
        let record = SwiftInferCommand.Verify.surveyErrorRecord(
            SwiftInferCommand.Verify.recordContext(for: Self.entry(tier: "Possible")),
            .architecturalCoveragePending,
            "unsupported-carrier: Foo"
        )
        let data = try JSONEncoder().encode(record)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"tier\":\"Possible\""), """
        The encoded record does not carry the tier: \(text). A consumer would have to \
        join an index back in, which is the failure this field removes.
        """)
    }

    /// **Optional on purpose.** Streams frozen before 2026-08-19 do not carry it, and a
    /// consumer must be able to tell *absent* from *`Advisory`* — `analyse.py` says so
    /// out loud rather than reporting the total as if it were the ratio.
    @Test("an absent tier decodes as nil rather than a value")
    func absentTierDecodesAsNil() throws {
        let json = """
        {"identityHash":"0x1","templateName":"idempotence","primaryFunctionName":"f",
         "carrier":"C","outcome":"measured-bothPass","outcomeDetail":"d"}
        """
        let record = try JSONDecoder().decode(
            SwiftInferCommand.Verify.SurveyRecord.self, from: Data(json.utf8)
        )
        #expect(record.tier == nil)
    }
}
