import Foundation
@testable import SwiftInferCLI
@testable import SwiftInferCore
import Testing

/// The async-veto relaxation on the generic-laws path (collections/async
/// workplan Phase 4): a seeded `async` function synthesizes a determinism
/// law only when it carries the clock-determinism claim — the conjunction
/// posture. Bare async stays vetoed, exactly as before.
@Suite
struct AsyncDeterminismLawTests {

    @Test("Clock-deterministic-annotated async function earns the determinism law")
    func annotatedAsyncSynthesizesDeterminism() throws {
        let directory = try writeDPFixture(name: "AsyncGenericLaw", contents: """
        /// @lint.determinism clock_deterministic
        func fetchLabel(_ n: Int) async -> String { "#\\(n)" }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 2, symbol: "fetchLabel")])
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording
        )
        #expect(recording.text.contains("Template: determinism"))
        #expect(recording.text.contains("fetchLabel(_:)"))
        #expect(recording.text.contains("(Int) async -> String"))
        #expect(recording.text.contains("Clock-deterministic-annotated async function"))
    }

    @Test("Bare async function stays vetoed on the generic-laws path")
    func bareAsyncStaysVetoed() throws {
        let directory = try writeDPFixture(name: "AsyncGenericVeto", contents: """
        func plainFetch(_ n: Int) async -> String { "#\\(n)" }
        """)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = SeedManifest(seeds: [.init(file: "Source.swift", line: 1, symbol: "plainFetch")])
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: false,
            seedManifest: manifest,
            output: recording
        )
        #expect(recording.text.contains("Template: determinism") == false)
    }
}
