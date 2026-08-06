import Foundation
@testable import SwiftInferCore
import Testing

@Suite("SeedFocus — manifest decoding + symbol parsing")
struct SeedFocusTests {

    @Test("functionBaseName strips parameter labels")
    func stripsParameterLabels() {
        #expect(SeedFocus.functionBaseName("add(_:_:)") == "add")
        #expect(SeedFocus.functionBaseName("normalize(_:)") == "normalize")
        #expect(SeedFocus.functionBaseName("area(width:height:)") == "area")
    }

    @Test("functionBaseName returns a paren-less name unchanged")
    func parenlessUnchanged() {
        #expect(SeedFocus.functionBaseName("identity") == "identity")
        #expect(SeedFocus.functionBaseName("").isEmpty)
    }

    // MARK: - `kind` — a seed is not always a symbol to analyse

    /// This used to assert the opposite — that a seed with no `kind` defaults to `.pureFunction`,
    /// so a v1 manifest still decoded. No v1 manifest can exist any more: the producer's version is
    /// a constant 2, and manifests are generated on demand rather than archived.
    ///
    /// The tolerance had to go rather than merely being unused, because it was a SILENT default on
    /// the one field whose misreading the v1 -> v2 bump was created to prevent. A producer that
    /// dropped `kind` through a bug would have every seed read as analysable, and discovery would
    /// narrow onto uncallable kernels and report a confident zero.
    @Test("a seed with no kind is rejected rather than assumed analysable")
    func missingKindIsRejected() {
        let json = """
        { "version": 2, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "rule": "Pure Function Property-Test Candidate" }
        ] }
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        }
    }

    @Test("an extractable kernel is reported, never focused on")
    func kernelIsNotAnalysable() throws {
        // The reason `kind` exists. A kernel has no name yet — nothing to index, nothing to call.
        // Its symbol names the *impure method the logic is trapped inside*, so focusing on it would
        // narrow the run to a function this tool must then refuse (`private async throws` refutes
        // purity) and report `kept 0` for a codebase that demonstrably has property-testable logic
        // in it. That is the empty-manifest bug arriving by a new route.
        let json = """
        { "version": 2, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "kind": "pure-function",
              "rule": "Pure Function Property-Test Candidate"},
            { "file": "Upload.swift", "line": 73, "symbol": "uploadRemainingChunks",
              "kind": "extractable-kernel", "rule": "Pure Function Property-Test Candidate"}
        ] }
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))

        #expect(manifest.seeds.count == 2)
        #expect(manifest.analysableSeeds.map(\.symbol) == ["add"])
        #expect(manifest.refactorPendingSeeds.map(\.symbol) == ["uploadRemainingChunks"])
    }

    @Test("an unrecognised kind is not focused on, and keeps its raw name for the warning")
    func unknownKindIsNotAnalysable() throws {
        // The two ways to be wrong here are not symmetric. Guess "analysable" and a future
        // refactor-pending kind gets focused on, refused, and reported as a zero — silently. Guess
        // "not analysable" and the seed is merely skipped, and said out loud. Never silently narrow
        // to a symbol whose meaning you do not know.
        let json = """
        { "version": 3, "seeds": [
            { "file": "View.swift", "line": 57, "symbol": "fetchLocalFiles", "kind": "pure-closure",
              "rule": "Pure Function Property-Test Candidate"}
        ] }
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))

        let seed = try #require(manifest.seeds.first)
        #expect(seed.kind == .unrecognised("pure-closure"))
        #expect(seed.kind.isAnalysable == false)
        #expect(seed.kind.rawValue == "pure-closure")
        #expect(manifest.analysableSeeds.isEmpty)
    }

    @Test("only analysable seeds focus")
    func focusIgnoresKernels() {
        // A manifest of kernels alone must not filter anything away — there is nothing to focus on,
        // and narrowing to zero would be the confident zero all over again.
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(
                file: "Upload.swift", line: 73, symbol: "uploadRemainingChunks",
                kind: .extractableKernel
            )
        ])

        let suggestions = SeedFocus.filter([], to: manifest)
        #expect(suggestions.isEmpty)
        #expect(manifest.analysableSeeds.isEmpty)
    }

    @Test("SeedManifest decodes the producer's pbt-seeds shape")
    func decodesProducerShape() throws {
        let json = """
        { "version": 2, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "kind": "pure-function",
              "rule": "Pure Function Property-Test Candidate" }
        ] }
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        #expect(manifest.version == 2)
        #expect(manifest.seeds.count == 1)
        #expect(manifest.seeds.first?.symbol == "add")
        #expect(manifest.seeds.first?.rule == "Pure Function Property-Test Candidate")
    }

    /// **This test asserted the opposite until 2026-08-06**, and the reversal is deliberate.
    ///
    /// `rule` was decoded leniently on the theory that a producer might drop or rename it. No
    /// producer does: `PBTSeed.rule` is a non-optional `String` written from `issue.ruleName` on
    /// every seed, and 0 of 2,099 measured seeds lacked it. So the tolerance never tolerated
    /// anything real — it only guaranteed that a genuinely malformed manifest would parse into
    /// seeds whose provenance nothing could name.
    ///
    /// Which mattered because **nothing read the field at all**. It was decoded and stored from the
    /// day it existed and consulted nowhere, while `discover`'s warnings reported an unreadable
    /// `kind` without saying which rule produced it — the one thing that turns "upgrade the tool"
    /// into "and here is which half moved".
    ///
    /// Same reasoning as `kind`, one field over: a silent default on a field the producer always
    /// sends is a hatch that only ever admits bugs.
    @Test("SeedManifest refuses a seed with no rule")
    func refusesMissingRule() throws {
        let json = #"""
        { "version": 2, "seeds": [
            { "file": "A.swift", "line": 1, "symbol": "f", "kind": "pure-function" }
        ] }
        """#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        }
    }

    /// The control: identical document with the field, so the refusal above is attributable to
    /// `rule` alone.
    @Test("the same manifest with a rule decodes")
    func decodesWithRule() throws {
        let json = #"""
        { "version": 2, "seeds": [
            { "file": "A.swift", "line": 1, "symbol": "f", "kind": "pure-function",
              "rule": "Pure Function Property-Test Candidate" }
        ] }
        """#
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        #expect(manifest.seeds.first?.rule == "Pure Function Property-Test Candidate")
        #expect(manifest.seeds.first?.symbol == "f")
    }
}
