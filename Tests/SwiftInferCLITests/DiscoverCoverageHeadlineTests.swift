import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// **A `discover` count must never be rendered alone.**
///
/// The repo owner's thought experiment is what these tests defend: *if PropertyLawKit were
/// perfect at finding testable properties, there would be nothing left to discover.* A tool
/// reporting `0 suggestions.` would then be reporting total success in the exact typography
/// of total failure — which is why the `fixtures/leaderboard-sort` scorecards were withdrawn,
/// and why the standing instruction is that discover-only numbers are pointless.
///
/// Twelve pipeline tests assert on the suggestion body via `DPRecordingOutput.body`, which
/// strips the headline. Without the tests below, deleting the headline entirely would leave
/// the whole suite green.
@Suite("Discover — the coverage headline is not optional")
struct DiscoverCoverageHeadlineTests {

    @Test("every discover render leads with the coverage line")
    func headlineIsPresent() throws {
        let directory = try writeDPFixture(name: "CoverageHeadline", contents: """
        struct Money: Equatable, Hashable {
            let amount: Int
        }
        struct Sanitizer {
            func normalize(_ value: Money) -> Money { normalize(normalize(value)) }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text.hasPrefix("Coverage: discover proposes "))
        #expect(recording.text.contains("PropertyLawKit's suites cover"))
        // The two carriers above are Equatable + Hashable, so the kit genuinely covers laws
        // here. A zero would mean the audit stopped reaching the conformance index.
        #expect(!recording.text.contains("cover 0 laws"), "Equatable + Hashable is not zero")
    }

    /// **An empty corpus still gets the line.** Suppressing it when there is nothing to say
    /// would reintroduce the silence the headline exists to remove — and the empty run is
    /// exactly where a bare `0 suggestions.` misleads most.
    @Test("an empty corpus still reports coverage, including a zero")
    func emptyCorpusStillReportsCoverage() throws {
        let directory = try makeDPFixtureDirectory(name: "CoverageHeadlineEmpty")
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            output: recording
        )
        #expect(recording.text.hasPrefix("Coverage: discover proposes 0;"))
        #expect(recording.body == "0 suggestions.", "the body itself is unchanged")
    }

    /// `--stats-only` is the mode a CI dashboard calls, so it is the one where a naked number
    /// would do the most damage.
    @Test("--stats-only carries the headline too")
    func statsOnlyCarriesTheHeadline() throws {
        let directory = try writeDPFixture(name: "CoverageHeadline", contents: """
        struct Money: Equatable {
            let amount: Int
        }
        struct Sanitizer {
            func normalize(_ value: Money) -> Money { normalize(normalize(value)) }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            statsOnly: true,
            output: recording
        )
        #expect(recording.text.hasPrefix("Coverage: discover proposes "))
    }

    /// Laws, not carriers. Reporting `discover: 22` beside `kit: 297 carriers` is the unit
    /// confusion `ProtocolCoverageAudit` already shipped once — *"150 carrier(s) had laws
    /// suppressed"* on a target whose measured suppression was zero.
    @Test("the headline counts laws, and says so")
    func headlineCountsLaws() {
        let line = CoverageHeadline.line(
            suggestionCount: 22,
            lawCount: 996,
            carrierCount: 299,
            evidenceState: .noEvidence
        )
        #expect(line.contains("996 laws over 299 carriers"))
        #expect(line.contains("discover proposes 22"))
    }

    @Test("singulars read correctly")
    func singularAgreement() {
        let line = CoverageHeadline.line(
            suggestionCount: 1, lawCount: 1, carrierCount: 1, evidenceState: .ran
        )
        #expect(line.contains("1 law over 1 carrier"))
        #expect(!line.contains("1 laws"))
        #expect(!line.contains("1 carriers"))
    }

    /// The three evidence states must be distinguishable in the text, or the line cannot
    /// tell "the kit ran" from "nothing checked these".
    @Test("each evidence state says something different")
    func evidenceStatesDiffer() {
        func line(_ state: CoverageHeadline.EvidenceState) -> String {
            CoverageHeadline.line(
                suggestionCount: 5, lawCount: 10, carrierCount: 3, evidenceState: state
            )
        }
        let ran = line(.ran)
        let none = line(.noEvidence)
        let missed = line(.ranButMissed(carriers: 2))
        #expect(ran != none)
        #expect(none != missed)
        #expect(ran.contains("confirms they ran"))
        #expect(none.contains("no kit evidence"))
        #expect(missed.contains("checked by nothing"))
    }
}
