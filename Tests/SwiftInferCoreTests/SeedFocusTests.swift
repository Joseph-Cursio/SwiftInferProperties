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

    @Test("a v1 manifest has no kind, and every seed in one was analysable")
    func legacyManifestDefaultsToAnalysable() throws {
        let json = """
        { "version": 1, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "rule": "Pure Function Property-Test Candidate" }
        ] }
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))

        #expect(manifest.seeds.first?.kind == .pureFunction)
        #expect(manifest.analysableSeeds.count == 1)
        #expect(manifest.refactorPendingSeeds.isEmpty)
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
            { "file": "Math.swift", "line": 3, "symbol": "add", "kind": "pure-function" },
            { "file": "Upload.swift", "line": 73, "symbol": "uploadRemainingChunks",
              "kind": "extractable-kernel" }
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
            { "file": "View.swift", "line": 57, "symbol": "fetchLocalFiles", "kind": "pure-closure" }
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
        { "version": 1, "seeds": [
            { "file": "Math.swift", "line": 3, "symbol": "add", "rule": "Pure Function Property-Test Candidate" }
        ] }
        """
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        #expect(manifest.version == 1)
        #expect(manifest.seeds.count == 1)
        #expect(manifest.seeds.first?.symbol == "add")
        #expect(manifest.seeds.first?.rule == "Pure Function Property-Test Candidate")
    }

    @Test("SeedManifest tolerates a missing rule field")
    func toleratesMissingRule() throws {
        let json = #"{ "version": 1, "seeds": [ { "file": "A.swift", "line": 1, "symbol": "f" } ] }"#
        let manifest = try JSONDecoder().decode(SeedManifest.self, from: Data(json.utf8))
        #expect(manifest.seeds.first?.rule == nil)
        #expect(manifest.seeds.first?.symbol == "f")
    }
}
