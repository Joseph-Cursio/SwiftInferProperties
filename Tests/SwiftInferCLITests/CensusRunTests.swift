import Foundation
import Testing

@testable import SwiftInferCLI

/// A census records its denominator, and the arms here are about the ways that can silently stop
/// being true.
///
/// The command exists because two census conclusions turned out to be correct counts under a
/// misremembered corpus list. So the invariants worth guarding are not the arithmetic — that is
/// a dictionary merge — but the things that make a count readable a month later: the corpus list
/// survives a round trip, a zero is reported against the catalog the reader supplies rather than
/// against whatever fired, and the run cannot claim to be wider than it was.
@Suite("A census records the corpus list it was taken over")
struct CensusRunTests {

    private static func member(
        _ id: String,
        rows: [String: Int],
        revision: String? = String(repeating: "a", count: 40),
        dirty: Bool = false,
        pin: String = "at-pin"
    ) -> CensusRun.Member {
        CensusRun.Member(id: id, revision: revision, dirty: dirty, pin: pin, rowsByTemplate: rows)
    }

    private static func run(_ members: [CensusRun.Member]) -> CensusRun {
        CensusRun(
            schemaVersion: CensusRun.currentSchemaVersion,
            label: "fixture",
            capturedAt: Date(timeIntervalSince1970: 0),
            flags: "--include-possible",
            swiftInferVersion: "1.149.0",
            corpora: members
        )
    }

    // MARK: - The denominator

    @Test("The corpus list survives a round trip, ids and order intact")
    func denominatorRoundTrips() throws {
        let original = Self.run([
            Self.member("swiftlang-swift", rows: ["idempotence": 398]),
            Self.member("swift-nio", rows: ["idempotence": 12, "round-trip": 3])
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("census-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try CensusRun.write(original, to: url)
        let decoded = try CensusRun.read(from: url)

        #expect(decoded.corpora.map(\.id) == ["swiftlang-swift", "swift-nio"])
        #expect(decoded.flags == "--include-possible")
        #expect(decoded.total == 413)
    }

    /// The whole point, in one arm: a template that fired nowhere is **absent from the counts**,
    /// so it can only be named against a catalog supplied from outside.
    ///
    /// If this ever became derivable from the run alone, the run would be claiming to know every
    /// template that could have fired — which is the over-confidence the command refuses.
    @Test("A zero is reported against the supplied catalog, not against what fired")
    func zeroesAreRelativeToTheCatalog() {
        let census = Self.run([Self.member("swift-nio", rows: ["idempotence": 12])])

        #expect(census.zeroRowTemplates(against: ["idempotence", "involution"]) == ["involution"])
        // A narrower catalog cannot invent a zero, and a wider one finds more of them: the
        // answer moves with the catalog, which is exactly the dependency being made explicit.
        #expect(census.zeroRowTemplates(against: ["idempotence"]).isEmpty)
        #expect(
            census.zeroRowTemplates(against: ["a", "b", "idempotence"]) == ["a", "b"],
            "a zero is a fact about the template AND the list, and both must be arguments"
        )
    }

    @Test("Rows sum across corpora, per template")
    func rowsSumAcrossCorpora() {
        let census = Self.run([
            Self.member("one", rows: ["idempotence": 3, "round-trip": 1]),
            Self.member("two", rows: ["idempotence": 4])
        ])
        #expect(census.rowsByTemplate == ["idempotence": 7, "round-trip": 1])
        #expect(census.corpora.map(\.total) == [4, 4])
    }

    // MARK: - The caveats that must not be lost

    /// A dirty tree means the counts include uncommitted work and the revision does not name
    /// what was surveyed. Stored, not just printed: the person reading the artifact next month
    /// is not the person who saw stderr.
    @Test("A dirty tree and a null revision both survive into the artifact")
    func caveatsAreStoredNotJustPrinted() throws {
        let original = Self.run([
            Self.member("dirty-one", rows: ["idempotence": 1], dirty: true),
            Self.member("untracked", rows: [:], revision: nil, pin: "uncheckable")
        ])
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("census-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        try CensusRun.write(original, to: url)
        let decoded = try CensusRun.read(from: url)

        #expect(decoded.corpora[0].dirty)
        #expect(decoded.corpora[1].revision == nil)
        #expect(decoded.corpora[1].pin == "uncheckable")
    }

    /// The rendered report must name the corpus list, and must say what a zero means, **every
    /// time**. A caveat printed only when someone judges it interesting is one that goes missing
    /// on the run that needed it.
    @Test("The report names the denominator and qualifies every zero")
    func reportCarriesTheDenominatorAndTheCaveat() {
        let text = CensusRenderer.render(
            Self.run([
                Self.member("swift-nio", rows: ["idempotence": 12]),
                Self.member("swift-syntax", rows: ["round-trip": 5])
            ]),
            wroteTo: nil
        )
        #expect(text.contains("swift-nio"))
        #expect(text.contains("swift-syntax"))
        #expect(text.contains("denominator"))
        #expect(
            text.contains("ACROSS THESE 2 CORPORA"),
            "the caveat must carry the count, or it reads as a claim about the catalog"
        )
        #expect(text.contains("--include-possible"), "flags move the headline by 20%")
    }

    /// A corpus contributing nothing must be visible as such in the report.
    ///
    /// **The regression this pins is `swift-collections`.** Its registered target `Collections`
    /// is a real, buildable SwiftPM target and a **pure re-export umbrella** — five
    /// `… reexports.swift` files of typealiases, zero declarations — so the census scanned real
    /// files and found no API, and printed `0 rows` next to corpora printing four figures. Once
    /// the entry gained `sources: "Sources"` the same corpus reports **1,012 rows over 23
    /// templates**.
    ///
    /// A zero row is legitimate and is also exactly what a wrong scan path looks like, so the
    /// command warns rather than refuses — but the *report* must never let a zero pass as an
    /// ordinary row, because the first one was caught by eye in a table, which is not a
    /// mechanism.
    @Test("A corpus that contributed nothing is still named in the report, with its zero")
    func aZeroContributorIsNamed() {
        let text = CensusRenderer.render(
            Self.run([
                Self.member("umbrella-target", rows: [:]),
                Self.member("real-code", rows: ["idempotence": 12])
            ]),
            wroteTo: nil
        )
        #expect(
            text.contains("umbrella-target"),
            "a corpus contributing nothing must still appear in the denominator it belongs to"
        )
        #expect(text.contains("0 rows"), "its zero must be shown, not elided")
        #expect(text.contains("ACROSS THESE 2 CORPORA"), "the zero corpus still counts as surveyed")
    }

    /// `CorpusPin.token` is stored in the artifact, so it is a contract rather than copy.
    ///
    /// The rendered sentences beside it have been reworded twice this month. If the artifact
    /// stored those, two censuses a month apart would disagree about a corpus that never moved.
    @Test("Pin tokens are stable and distinguish every state")
    func pinTokensAreDistinct() {
        let tokens: [String] = [
            CorpusPin.noBaseline.token,
            CorpusPin.uncheckable.token,
            CorpusPin.revisionUnrecoverable.token,
            CorpusPin.atPin(dirty: false).token,
            CorpusPin.atPin(dirty: true).token,
            CorpusPin.movedOff(head: "a", pinned: "b", dirty: false).token,
            CorpusPin.movedOff(head: "a", pinned: "b", dirty: true).token
        ]
        #expect(Set(tokens).count == tokens.count, "two states sharing a token: \(tokens)")
        #expect(tokens.allSatisfy { !$0.contains(" ") }, "a token with a space is a sentence")
    }
}
