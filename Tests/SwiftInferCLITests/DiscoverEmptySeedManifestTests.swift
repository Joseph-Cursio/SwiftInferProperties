import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// An empty seed manifest must not focus the run to nothing.
///
/// The manifest is not authored by hand — it is whatever the producing linter happened to find.
/// A linter with a blind spot emits an empty manifest, and a filter that reads "focus on these
/// zero functions" as "keep zero suggestions" then discards every genuine suggestion and reports
/// a confident `0 suggestions.` This made running the documented `lint → infer` pipeline
/// **strictly worse** than running `swift-infer` on its own: the linter cannot see instance
/// methods, so on ordinary app code it hands over nothing, and six real suggestions became zero.
///
/// Nobody asks to focus on nothing. An empty manifest is what a producer that found nothing looks
/// like, and the honest response is to say so and not filter.
@Suite("Discover pipeline — an empty --seeds manifest does not focus to nothing")
struct DiscoverEmptySeedManifestTests {

    /// Two idempotent functions, neither of which any linter seeded.
    private static let twoCandidates = """
    struct Sanitizer {
        func normalize(_ value: String) -> String {
            return normalize(normalize(value))
        }
        func sanitize(_ value: String) -> String {
            return sanitize(sanitize(value))
        }
    }
    """

    // MARK: - A manifest of kernels is not a manifest of nothing

    @Test("an extractable kernel is announced, never focused on")
    func kernelIsReportedRatherThanFocusedOn() throws {
        // A kernel seed's symbol names the *impure method the pure logic is trapped inside*. Focus
        // on it and this tool must refuse the function (async/throws refute purity) and then report
        // `kept 0` for a codebase with property-testable logic in it — the confident zero this suite
        // exists to prevent, arriving by a new route.
        //
        // So it is neither focused on nor silently dropped: it is NAMED, with the one instruction
        // that unblocks it.
        let directory = try writeDPFixture(name: "SeedsKernel", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: SeedManifest(seeds: [
                SeedManifest.Seed(
                    file: "Upload.swift", line: 73, symbol: "uploadRemainingChunks",
                    kind: .extractableKernel
                )
            ]),
            output: recording,
            diagnostics: diagnostics
        )

        // Named, with its location and its remedy.
        #expect(diagnostics.joined.contains("1 extractable kernel(s)"))
        #expect(diagnostics.joined.contains("uploadRemainingChunks"))
        #expect(diagnostics.joined.contains("extract it into a named value type"))

        // And the run was NOT narrowed to it: both real suggestions survive.
        #expect(recording.text.contains("normalize(_:)"))
        #expect(recording.text.contains("sanitize(_:)"))

        // The "no analysable seeds" warning must not claim the manifest was empty — it was not, and
        // the remedy for "the linter found nothing" is the opposite of "extract these first".
        #expect(diagnostics.joined.contains("must be done by hand first"))
        #expect(diagnostics.joined.contains("the seeds manifest is empty") == false)
    }

    @Test("an unrecognised kind is skipped loudly, not focused on silently")
    func unknownKindWarns() throws {
        let directory = try writeDPFixture(name: "SeedsUnknown", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: SeedManifest(seeds: [
                SeedManifest.Seed(
                    file: "View.swift", line: 57, symbol: "fetchLocalFiles",
                    kind: .unrecognised("pure-closure")
                )
            ]),
            output: recording,
            diagnostics: diagnostics
        )

        #expect(diagnostics.joined.contains("warning"))
        #expect(diagnostics.joined.contains("'pure-closure', which this build does not recognise"))
        #expect(recording.text.contains("normalize(_:)"))
    }

    @Test("an empty manifest surfaces every suggestion rather than none")
    func emptyManifestDoesNotFocusToNothing() throws {
        let directory = try writeDPFixture(name: "SeedsEmpty", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: SeedManifest(seeds: []),
            output: recording,
            diagnostics: diagnostics
        )

        // The whole point: the same two suggestions the unfocused run finds.
        #expect(recording.text.contains("2 suggestions."))
        #expect(recording.text.contains("normalize(_:)"))
        #expect(recording.text.contains("sanitize(_:)"))
    }

    @Test("an empty manifest warns that it applied no focus, and why")
    func emptyManifestWarnsLoudly() throws {
        let directory = try writeDPFixture(name: "SeedsEmptyWarn", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: SeedManifest(seeds: []),
            output: recording,
            diagnostics: diagnostics
        )

        // Silently doing the right thing is not enough — the reader has to learn that their
        // linter produced nothing, or they will believe the manifest was fine and the code is bare.
        #expect(diagnostics.joined.contains("warning"))
        #expect(diagnostics.joined.contains("empty"))
        #expect(diagnostics.joined.contains("no focus"))
    }

    @Test("seeds that match nothing keep the focus, but warn that they emptied the run")
    func nonMatchingSeedsWarn() throws {
        let directory = try writeDPFixture(name: "SeedsNoMatch", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A seed naming a function that is not among the suggestions. The user did ask to focus,
        // so the focus is honoured — but a run that discards everything must never look like a
        // run that found nothing.
        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 1, symbol: "noSuchFunction", rule: nil)
        ])

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        #expect(diagnostics.joined.contains("warning"))
        // "analysable" now qualifies the count, because a manifest can also carry seeds that name
        // work a human must do first — and those never focus, so they must not be counted here.
        #expect(diagnostics.joined.contains("none of the 1 analysable seed(s) matched"))
    }

    @Test("a matching manifest still focuses — the fix does not disable seeding")
    func matchingManifestStillFocuses() throws {
        let directory = try writeDPFixture(name: "SeedsStillFocus", contents: Self.twoCandidates)
        defer { try? FileManager.default.removeItem(at: directory) }

        let manifest = SeedManifest(seeds: [
            .init(file: "Source.swift", line: 2, symbol: "normalize", rule: nil)
        ])

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        #expect(recording.text.contains("normalize(_:)"))
        #expect(!recording.text.contains("sanitize(_:)"))
    }
}
