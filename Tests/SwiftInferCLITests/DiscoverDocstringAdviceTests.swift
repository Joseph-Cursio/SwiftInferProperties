import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// End-to-end wiring for `discover --docstring-advice`.
///
/// The decision logic is unit-tested in `DocstringAdvisorTests` (Core); these
/// tests exercise the CLI path: the block is emitted **by default**, the
/// `--no-docstring-advice` / config opt-out suppresses it, and the two shapes
/// reach the reader with the right function attached.
///
/// The default flipped on the SwiftProjectLint road test (2026-07-24), which
/// measured *reach* rather than the reader lift the original A/B measured: a
/// default run surfaced 2 of 10 hand-keyed kernels with a refutable law, and
/// this advisory surfaced 8. See `Config.docstringAdvice` for the full framing,
/// including what that number does and does not claim.
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

    @Test("with no flag at all, the docstring block IS emitted")
    func onByDefault() throws {
        let directory = try writeDPFixture(name: "DocAdviceDefault", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            seedManifest: manifest(),
            output: recording
        )
        #expect(recording.text.contains("Reference definitions from docstrings"))
        #expect(recording.text.contains("isValidName"))
    }

    @Test("--no-docstring-advice suppresses the block")
    func explicitOptOutSuppressesTheBlock() throws {
        let directory = try writeDPFixture(name: "DocAdviceOff", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: false,
            seedManifest: manifest(),
            output: recording
        )
        #expect(recording.text.contains("Reference definitions from docstrings") == false)
    }

    /// Precedence is CLI > config > default, the same shape `includePossible`
    /// uses. A project that finds the advisory noisy turns it off once in
    /// `.swiftinfer/config.toml`; a reader who wants it back for one run passes
    /// the flag and wins.
    @Test("config can turn the block off, and an explicit flag overrides config")
    func configOptOutIsOverriddenByTheFlag() throws {
        let directory = try writeDPFixture(name: "DocAdviceConfig", contents: Self.source)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configPath = directory.appendingPathComponent("off-config.toml")
        try "[discover]\ndocstringAdvice = false\n".write(
            to: configPath, atomically: true, encoding: .utf8
        )

        let viaConfig = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            explicitConfigPath: configPath,
            seedManifest: manifest(),
            output: viaConfig
        )
        #expect(viaConfig.text.contains("Reference definitions from docstrings") == false)

        let flagWins = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            explicitConfigPath: configPath,
            docstringAdvice: true,
            seedManifest: manifest(),
            output: flagWins
        )
        #expect(flagWins.text.contains("Reference definitions from docstrings"))
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
        // B25 (issue #1) — the runnable reference-oracle scaffold: a stub the
        // reader fills and the predicate-vs-oracle property the machine runs.
        #expect(recording.text.contains("runnable reference oracle"))
        #expect(recording.text.contains("func isValidName_reference(_ name: String) -> Bool"))
        #expect(recording.text.contains("isValidName(value) == isValidName_reference(value)"))
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

    @Test("a comparator gets an ordering-key oracle — the SWO law can't say which ordering")
    func comparatorOrderingKey() throws {
        let source = """
        struct Entry { let size: Int; let name: String }
        /// Orders entries by size ascending, then by name in ascending lexicographic order.
        func precedes(_ lhs: Entry, _ rhs: Entry) -> Bool {
            lhs.size != rhs.size ? lhs.size < rhs.size : lhs.name.count < rhs.name.count
        }
        """
        let directory = try writeDPFixture(name: "DocAdviceComparator", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: true,
            seedManifest: SeedManifest(seeds: [.init(file: "Source.swift", line: 3, symbol: "precedes")]),
            output: recording
        )
        #expect(recording.text.contains("precedes"))
        // Comparator-specific framing: the SWO law checks validity, the docstring the key.
        #expect(recording.text.contains("strict-weak-ordering law checks this is a VALID ordering"))
        // The ordering-key oracle stub + the comparator-vs-oracle property (two operands).
        #expect(recording.text.contains("func precedes_reference(_ lhs: Entry, _ rhs: Entry) -> Bool"))
        #expect(recording.text.contains(
            "precedes(tuple.0, tuple.1) == precedes_reference(tuple.0, tuple.1)"
        ))
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
