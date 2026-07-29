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

    /// A manifest is written for a whole project; a `discover` run covers one target, so
    /// "focused on 145 analysable seed(s)" for a target holding one made a healthy run read as a
    /// catastrophic one.
    ///
    /// Only the COUNT is scoped. Scoping the focus SET was tried and reverted: `PipelineResult`
    /// carries no list of files actually read, so "in scope" has to be approximated from analysis
    /// outputs, and every approximation loses a category — access-restricted functions produce no
    /// summary, and a file with no analysable subject at all is indistinguishable from a file in
    /// another target. Both losses broke real behaviour elsewhere in this suite.
    @Test("the focus count says how many seeds are under the scanned sources")
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

        // All three are focused on; one is under the scanned sources, and the line says so.
        #expect(diagnostics.joined.contains("focused on 3 analysable seed(s)"))
        #expect(diagnostics.joined.contains("(1 under the scanned sources)"))
    }
}
