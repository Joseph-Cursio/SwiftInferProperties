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
///
/// Every manifest here seeds every documented function, so these tests see only the full
/// block. Under `--seeds` the advice is split in two — the full block for the functions the
/// manifest names as functions to analyse, and a compact "Documented contracts outside the seed
/// focus" block for the rest — and that split is `DiscoverDocstringAdviceSeedFocusTests`'s
/// subject. The 8 of 10 was measured without seeds.
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
        // `isValidName` is an instance method, so its reference is declared on `Files` and the
        // property draws a `Files` receiver — stateless, so it derives as `Gen.always(Files())`.
        #expect(recording.text.contains("""
                extension Files {
                    func isValidName_reference(_ name: String) -> Bool {
            """))
        #expect(recording.text.contains(
            "{ (args: (Files, String)) in args.0.isValidName(args.1) == args.0.isValidName_reference(args.1) }"
        ))
        #expect(recording.text.contains("let arg0 = (Gen.always(Files())).run(using: &rng)"))
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
            "{ (args: (Entry, Entry)) in precedes(args.0, args.1) == precedes_reference(args.0, args.1) }"
        ))
    }

    /// **A tuple seed's scaffold.** With tuple-returning functions seeded, the synthesized
    /// determinism law is the source suggestion the fallback-contract scaffold needs, so a
    /// documented tuple function gains a reference oracle. It must declare the tuple as its return,
    /// compare by tuple `==`, and say what a tuple needs — not that the tuple "must be Equatable",
    /// which no tuple can be. The `Int`-returning neighbour is the control: its note is unchanged.
    @Test("a tuple-returning seed's reference oracle declares the tuple and says what it needs")
    func tupleReturningFallbackContract() throws {
        let source = """
        /// The clipped text never exceeds the byte budget.
        func clip(_ text: String, _ budget: Int) -> (text: String, didTruncate: Bool) {
            (String(text.prefix(budget)), text.count > budget)
        }

        /// Delay is capped at the ceiling and never negative.
        func backoffDelay(_ attempt: Int, _ ceiling: Int) -> Int { min(max(attempt * attempt, 0), ceiling) }
        """
        let directory = try writeDPFixture(name: "DocAdviceTuple", contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            docstringAdvice: true,
            seedManifest: SeedManifest(seeds: [
                .init(file: "Source.swift", line: 2, symbol: "clip"),
                .init(file: "Source.swift", line: 7, symbol: "backoffDelay")
            ]),
            output: recording
        )
        #expect(recording.text.contains("Reference definitions from docstrings"))
        #expect(recording.text.contains(
            "func clip_reference(_ text: String, _ budget: Int) -> (text: String, didTruncate: Bool)"
        ))
        #expect(recording.text.contains(
            "{ (args: (String, Int)) in clip(args.0, args.1) == clip_reference(args.0, args.1) }"
        ))
        #expect(recording.text.contains("every element of the returned tuple must be Equatable"))
        #expect(recording.text.contains("(text: String, didTruncate: Bool) must be Equatable") == false)
        #expect(recording.text.contains("// (the return type Int must be Equatable for this to compile)"))
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
        // `weighted`'s doc only narrates; it must not appear in the advice. `manifest()` seeds
        // every function, so only the full block is rendered here. The compact block is checked
        // for the same thing by `unseededContractIsListedNotHidden`, where `weighted` is unseeded.
        let advice = DiscoverDocstringAdviceSeedFocusTests.adviceRegion(of: recording.text)
        #expect(advice.contains("Reference definitions from docstrings"))
        #expect(advice.contains("convenience helper") == false)
    }
}
