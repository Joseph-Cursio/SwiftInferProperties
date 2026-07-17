import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// End-to-end wiring for `discover --docstring-advice`.
///
/// The decision logic is unit-tested in `DocstringAdvisorTests` (Core); these
/// tests exercise the CLI path: the flag gates the block, the block is off by
/// default (output stays byte-identical), and the two shapes reach the reader
/// with the right function attached.
@Suite("Discover — reference definitions from docstrings")
struct DiscoverDocstringAdviceTests {

    private static let source = """
    struct Files {
        /// A folder name is valid when it is non-empty and contains no slash.
        func isValidName(_ name: String) -> Bool { !name.isEmpty && !name.contains("/") }

        /// Delay is capped at the ceiling and never negative.
        func backoffDelay(_ attempt: Int, _ ceiling: Int) -> Int { min(max(attempt * attempt, 0), ceiling) }

        /// A convenience helper used by the ranking loop.
        func weighted(_ count: Int, _ weight: Int) -> Int { count * weight }
    }
    """

    private func manifest() -> SeedManifest {
        SeedManifest(seeds: [
            .init(file: "Source.swift", line: 3, symbol: "isValidName"),
            .init(file: "Source.swift", line: 6, symbol: "backoffDelay"),
            .init(file: "Source.swift", line: 9, symbol: "weighted")
        ])
    }

    @Test("without the flag, no docstring block is emitted")
    func offByDefault() throws {
        let directory = try writeDPFixture(name: "DocAdviceOff", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            seedManifest: manifest(),
            output: recording
        )
        #expect(!recording.text.contains("Reference definitions from docstrings"))
    }

    @Test("a predicate law's owed reference definition is filled by the docstring")
    func predicateReferenceDefinition() throws {
        let directory = try writeDPFixture(name: "DocAdvicePredicate", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: true,
            seedManifest: manifest(),
            output: recording
        )
        #expect(recording.text.contains("Reference definitions from docstrings"))
        #expect(recording.text.contains("isValidName"))
        #expect(recording.text.contains("the `predicate` law openly owes a reference definition"))
        #expect(recording.text.contains("non-empty and contains no slash"))
    }

    @Test("a function the templates can only tautologize gets its docstring as the fallback contract")
    func fallbackContractOnDeterminismOnly() throws {
        let directory = try writeDPFixture(name: "DocAdviceFallback", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: true,
            seedManifest: manifest(),
            output: recording
        )
        // Post-B24 the bare `(Int, Int) -> Int` shape no longer over-fires
        // associativity/commutativity, so `backoffDelay` reaches only the
        // determinism tautology — and the docstring is surfaced as the one
        // refutable contract the templates could not name.
        #expect(recording.text.contains("backoffDelay"))
        #expect(recording.text.contains("capped at the ceiling and never negative"))
        #expect(recording.text.contains("determinism tautology"))
    }

    @Test("a narrating docstring is not surfaced")
    func narrationIsNotSurfaced() throws {
        let directory = try writeDPFixture(name: "DocAdviceNarration", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: true,
            seedManifest: manifest(),
            output: recording
        )
        // `weighted`'s doc only narrates; it must not appear as a reference definition.
        let block = recording.text.components(separatedBy: "Reference definitions from docstrings").last ?? ""
        #expect(!block.contains("convenience helper"))
    }
}
