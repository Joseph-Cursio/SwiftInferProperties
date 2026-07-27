import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The focus set is scoped to the files this run actually scanned.
///
/// Split from `DiscoverPipelineSeedsTests` on the `type_body_length` cap. The subject is narrow
/// enough to stand alone: a manifest is written for a whole project while a `discover` run covers
/// one target, and every defect below comes from forgetting that.
@Suite("Discover — seed focus is scoped to the scanned sources")
struct DiscoverSeedScopeTests {

    // MARK: - The focus set is scoped to what was scanned

    /// A manifest is written for a whole project; a `discover` run covers one target.
    ///
    /// The focus set used to be the WHOLE manifest, which is the same defect
    /// `reportRefactorPending` had fixed one line earlier. It announced "focused on 145 analysable
    /// seed(s)" for a target holding six of them — a healthy run reading as a catastrophic one.
    ///
    /// It also removed a guard the join needs: `SeedFocus` matches on `(file basename, bare
    /// symbol)`, a key `inScope` exists because it collides across targets, so an out-of-target
    /// seed offered to the join can match an in-target suggestion for the wrong reason.
    @Test("seeds naming files this run never scanned are not counted as focused-on")
    func focusSetExcludesUnscannedSeeds() throws {
        let directory = try writeDPFixture(name: "SeedsScoped", contents: """
        struct Sanitizer {
            func normalize(_ value: String) -> String {
                return normalize(normalize(value))
            }
        }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("seeds.json")
        try Data("""
        { "version": 2, "seeds": [
            { "file": "Source.swift", "line": 2, "symbol": "normalize(_:)",
              "kind": "pure-function", "rule": "Pure Function Property-Test Candidate" },
            { "file": "SomeOtherTarget/Elsewhere.swift", "line": 9, "symbol": "faraway(_:)",
              "kind": "pure-function", "rule": "Pure Function Property-Test Candidate" },
            { "file": "AnotherTarget/AlsoAway.swift", "line": 4, "symbol": "distant(_:)",
              "kind": "pure-function", "rule": "Pure Function Property-Test Candidate" }
        ] }
        """.utf8).write(to: path)

        let recording = DPRecordingOutput()
        let diagnostics = DPRecordingDiagnosticOutput()
        let manifest = try SwiftInferCommand.Discover.loadSeedManifest(at: path)
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            seedManifest: manifest,
            output: recording,
            diagnostics: diagnostics
        )

        // One of the three seeds is in scope. The count must say one, not three.
        #expect(diagnostics.joined.contains("focused on 1 analysable seed(s)"))
        #expect(diagnostics.joined.contains("focused on 3 analysable seed(s)") == false)
    }
}
