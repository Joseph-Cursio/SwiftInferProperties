import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// `discover --seeds` and the docstring advisory: a focus that never hides a documented contract.
///
/// Until this suite, a seed manifest **dropped** the advice for every documented function it did
/// not name, with nothing said. The advisory went on by default on the strength of a road test run
/// *without* seeds (8 of 10 hand-keyed kernels), and the restriction underneath it was never looked
/// at again. Measured on SwiftAssist @52823df: 113 entries under `--seeds` against 286 without, the
/// 173 missing ones silently gone — including `stoppedEarly(_:limit:keeping:)` and
/// `prefix(utf8Bytes:)`, the two shapes the linter cannot seed (a generic carrier that is not
/// `Equatable`, and a tuple return).
///
/// The rule these tests pin: under a manifest the seeded advice stays in full, and every other
/// documented function a plain `discover` would advise on is listed in a compact second block,
/// "Documented contracts outside the seed focus". The two blocks together name exactly what a run
/// without seeds names. Which seeds focus mirrors `SeedFocus.filter`: analysable, non-carrier
/// seeds, and an empty or kernel-only manifest does not narrow at all.
@Suite("Discover — docstring advice outside the seed focus")
struct DiscoverDocstringAdviceSeedFocusTests {

    static let mainHeader = "Reference definitions from docstrings"
    static let compactHeader = "Documented contracts outside the seed focus"

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

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

    private static func seed(
        _ symbol: String,
        line: Int,
        kind: SeedKind = .pureFunction
    ) -> SeedManifest.Seed {
        .init(file: "Source.swift", line: line, symbol: symbol, kind: kind)
    }

    private func run(
        _ name: String,
        source: String = Self.source,
        manifest: SeedManifest?,
        docstringAdvice: Bool? = nil,
        statsOnly: Bool = false
    ) throws -> String {
        let directory = try writeDPFixture(name: name, contents: source)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recording = DPRecordingOutput()
        try SwiftInferCommand.Discover.run(
            directory: directory,
            includePossible: true,
            statsOnly: statsOnly,
            docstringAdvice: docstringAdvice,
            seedManifest: manifest,
            output: recording,
            diagnostics: SilentDiagnostics()
        )
        return recording.text
    }

    @Test("an unseeded documented contract is listed in brief, not hidden")
    func unseededContractIsListedNotHidden() throws {
        let text = try run("DocAdviceUnseeded", manifest: SeedManifest(seeds: [Self.seed("isValidName", line: 3)]))

        let main = Self.mainBlock(of: text)
        #expect(main.contains("the `predicate` law openly owes a reference definition"))
        #expect(main.contains("func isValidName_reference(_ name: String) -> Bool"))
        #expect(main.contains("backoffDelay") == false)

        let compact = Self.compactBlock(of: text)
        #expect(compact.contains("backoffDelay(_:_:)"))
        #expect(compact.contains("capped at the ceiling and never negative"))
        // The compact form carries no scaffold and none of the full form's claims: those describe
        // suggestions this reader is not shown, and "determinism tautology" is false here — no
        // determinism law is synthesized for a function the manifest does not name.
        #expect(compact.contains("runnable reference oracle") == false)
        #expect(compact.contains("determinism tautology") == false)
        #expect(compact.contains("encode THAT") == false)
        // Narration earns no place in either block.
        #expect(Self.adviceRegion(of: text).contains("convenience helper") == false)
    }

    /// The two SwiftAssist misses, reproduced without SwiftAssist: a tuple return (the shape of
    /// `prefix(utf8Bytes:)`) and a static factory on a generic, non-`Equatable` carrier returning
    /// `Self` (the shape of `CappedList.stoppedEarly`). The linter cannot seed either.
    @Test("shapes the linter cannot seed are listed outside the focus")
    func unseededShapesTheLinterCannotSeedAreListed() throws {
        let source = """
        /// A folder name is valid when it is non-empty and contains no slash.
        func isValidName(_ name: String) -> Bool { !name.isEmpty && !name.contains("/") }

        /// The longest prefix that fits in `limit` bytes; never longer than limit.
        func clip(_ text: String, _ limit: Int) -> (text: String, cut: Bool) {
            let kept = String(decoding: text.utf8.prefix(limit), as: UTF8.self)
            return (kept, kept.utf8.count < text.utf8.count)
        }

        struct Capped<Element> {
            let shown: [Element]

            /// Keeps at most `limit` elements, always the first ones.
            static func stoppedEarly(_ items: [Element], limit: Int) -> Self {
                Capped(shown: Array(items.prefix(limit)))
            }
        }
        """
        let text = try run(
            "DocAdviceUnseedableShapes",
            source: source,
            manifest: SeedManifest(seeds: [Self.seed("isValidName", line: 2)])
        )

        let compact = Self.compactBlock(of: text)
        #expect(compact.contains("clip(_:_:)"))
        #expect(compact.contains("never longer than limit"))
        #expect(compact.contains("stoppedEarly(_:limit:)"))
        #expect(compact.contains("always the first ones"))
        let main = Self.mainBlock(of: text)
        #expect(main.contains("clip(") == false)
        #expect(main.contains("stoppedEarly(") == false)
    }

    @Test("with no manifest there is no compact block, and the advice is what it always was")
    func noManifestIsUnchanged() throws {
        let text = try run("DocAdviceNoManifest", manifest: nil)

        #expect(text.contains(Self.compactHeader) == false)
        let main = Self.mainBlock(of: text)
        #expect(main.contains("backoffDelay(_:_:)"))
        #expect(main.contains("capped at the ceiling and never negative"))
        #expect(main.contains("determinism tautology"))
        #expect(main.contains("isValidName(_:)"))
    }

    @Test("a manifest naming every documented function adds no compact block")
    func fullySeededRunHasNoCompactBlock() throws {
        let manifest = SeedManifest(seeds: [
            Self.seed("isValidName", line: 3),
            Self.seed("backoffDelay", line: 6),
            Self.seed("weighted", line: 9)
        ])
        let text = try run("DocAdviceFullySeeded", manifest: manifest)

        #expect(text.contains(Self.compactHeader) == false)
        let main = Self.mainBlock(of: text)
        #expect(main.contains("isValidName(_:)"))
        #expect(main.contains("backoffDelay(_:_:)"))
    }

    /// The least-surprise invariant: seeding re-orders the advice into two blocks and never
    /// drops any of it.
    @Test("--seeds splits the docstring advice but never drops any of it")
    func seedsSplitButNeverDropDocstringAdvice() throws {
        let source = """
        struct Ledger {
            /// A folder name is valid when it is non-empty and contains no slash.
            func isValidName(_ name: String) -> Bool { !name.isEmpty && !name.contains("/") }

            /// Delay is capped at the ceiling and never negative.
            func backoffDelay(_ attempt: Int, _ ceiling: Int) -> Int { min(max(attempt * attempt, 0), ceiling) }

            /// Returns the balance rounded to the nearest whole unit.
            func wholeUnits(_ balance: Double) -> Int { Int(balance.rounded()) }
        }
        """
        let unseeded = try run("DocAdviceParityPlain", source: source, manifest: nil)
        let seeded = try run(
            "DocAdviceParitySeeded",
            source: source,
            manifest: SeedManifest(seeds: [Self.seed("backoffDelay", line: 6)])
        )

        let plainNames = Self.itemNames(in: Self.mainBlock(of: unseeded))
        let mainNames = Self.itemNames(in: Self.mainBlock(of: seeded))
        let compactNames = Self.itemNames(in: Self.compactBlock(of: seeded))
        #expect(plainNames.count == 3)
        #expect(mainNames == ["backoffDelay(_:_:)"])
        #expect(compactNames.isEmpty == false)
        #expect(mainNames.union(compactNames) == plainNames)
        #expect(mainNames.isDisjoint(with: compactNames))
    }

    /// `SeedFocus.filter` does not narrow on an empty manifest, nor on one holding only
    /// extractable-kernel seeds (`analysableSeeds` is empty). Docstring advice used to: an empty
    /// set of keys suppressed every entry, contradicting the `--seeds` help text.
    @Test(
        "an empty or kernel-only manifest does not narrow docstring advice",
        arguments: [
            SeedManifest(seeds: []),
            SeedManifest(seeds: [Self.seed("weighted", line: 9, kind: .extractableKernel)])
        ]
    )
    func emptyManifestDoesNotNarrowDocstringAdvice(manifest: SeedManifest) throws {
        let text = try run("DocAdviceEmptyManifest", manifest: manifest)

        #expect(text.contains(Self.compactHeader) == false)
        let main = Self.mainBlock(of: text)
        #expect(main.contains("backoffDelay(_:_:)"))
        #expect(main.contains("isValidName(_:)"))
    }

    /// A kernel seed's symbol names the impure method the kernel is trapped in (`SeedFocus`), so
    /// it says nothing about whether that method is worth a property test.
    @Test("an extractable-kernel seed does not vouch for its enclosing function")
    func kernelSeedDoesNotVouchForItsEnclosingFunction() throws {
        let manifest = SeedManifest(seeds: [
            Self.seed("isValidName", line: 3),
            Self.seed("backoffDelay", line: 6, kind: .extractableKernel)
        ])
        let text = try run("DocAdviceKernelSeed", manifest: manifest)

        #expect(Self.mainBlock(of: text).contains("backoffDelay") == false)
        #expect(Self.compactBlock(of: text).contains("backoffDelay(_:_:)"))
    }

    @Test("the opt-out and --stats-only suppress both blocks")
    func optOutSuppressesBothBlocks() throws {
        let partial = SeedManifest(seeds: [Self.seed("isValidName", line: 3)])

        let optedOut = try run("DocAdviceOptOutPartial", manifest: partial, docstringAdvice: false)
        #expect(optedOut.contains(Self.mainHeader) == false)
        #expect(optedOut.contains(Self.compactHeader) == false)

        let statsOnly = try run("DocAdviceStatsOnlyPartial", manifest: partial, statsOnly: true)
        #expect(statsOnly.contains(Self.mainHeader) == false)
        #expect(statsOnly.contains(Self.compactHeader) == false)
    }

    // MARK: - Slicing the output

    /// Everything from the first docstring-advice header on. Both blocks are appended last, so
    /// this is the advice and nothing else.
    static func adviceRegion(of text: String) -> String {
        let starts = [mainHeader, compactHeader].compactMap { text.range(of: $0)?.lowerBound }
        guard let start = starts.min() else { return "" }
        return String(text[start...])
    }

    /// The full block: from its header up to the compact header, or to the end.
    static func mainBlock(of text: String) -> String {
        guard let start = text.range(of: mainHeader)?.lowerBound else { return "" }
        let rest = text[start...]
        guard let end = rest.range(of: compactHeader)?.lowerBound else { return String(rest) }
        return String(rest[..<end])
    }

    /// The compact block: from its header to the end.
    static func compactBlock(of text: String) -> String {
        guard let start = text.range(of: compactHeader)?.lowerBound else { return "" }
        return String(text[start...])
    }

    /// The display names of a block's entries — each entry opens with `  • name(labels:)  `.
    static func itemNames(in block: String) -> Set<String> {
        Set(
            block.split(separator: "\n").compactMap { line -> String? in
                guard line.hasPrefix("  • ") else { return nil }
                let entry = line.dropFirst("  • ".count)
                return entry.components(separatedBy: "  ").first
            }
        )
    }
}
