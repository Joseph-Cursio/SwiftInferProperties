import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **The same census, re-taken across every corpus the manifest resolves.**
///
/// ## Why this arm exists
///
/// The home arm measured a base rate of **0** and said so with its reason attached:
/// the zero is a fact about *this subject*, which declares no file-scope `var` at
/// all, not a fact about the oracle. It closed with a standing instruction —
/// *"Do NOT carry this zero to another corpus"* — and then nobody carried it
/// anywhere for two days, which is the same thing as carrying it.
///
/// This arm is that instruction discharged. It runs the identical detector over the
/// 17 corpora `CorpusManifest` resolves, so the question changes from *does this
/// package exhibit the shape* to *does the shape exist in Swift as written*.
///
/// ## What differs from the home arm, and what deliberately does not
///
/// **The detector is the same object.** `FileScopeVarCollector` and
/// `ModuleStateWriteChecker` are reused, not re-implemented — a second detector
/// would make a disagreement between the arms unattributable.
///
/// **Globals are scoped per ROOT, which is the same rule.** The home arm groups by
/// `Sources/<Target>/` because a file-scope `var` is `internal` and visible exactly
/// within its module. Each manifest root already *is* a target directory, so
/// grouping by root preserves the rule rather than relaxing it. A corpus with
/// several roots keeps them separate; merging them would let a write in one module
/// match a `var` in another and inflate the count.
///
/// **Shadowing is still honoured**, and closures are still skipped as already
/// refuted by `refuteIfCaptured`.
///
/// ## The one thing this arm cannot claim
///
/// A hit here is a **false `.pure` in the oracle**, and that much is checkable. It
/// is *not* evidence that this package would ever ask the question — swift-infer
/// only runs the oracle over subjects it has picked. Reach and base rate are
/// separate, and this measures the second.
@Suite("Census — the module-state base rate across the manifest corpora", .serialized)
struct ModuleStateCorpusCensusMeasuredTests {

    struct Finding {
        let corpus: String
        let root: String
        let file: String
        let function: String
        let written: [String]
        let memberCalled: [String]
        let verdict: PurityVerdict
    }

    struct CorpusResult {
        let id: String
        let files: Int
        let functions: Int
        let globals: [String]
        /// Stored file-scope `var`s — mutable module state in the plain sense. The
        /// number that belongs in a base-rate denominator.
        let storedGlobals: [String]
        /// Computed file-scope `var`s. Counted, reported, and kept OUT of the
        /// denominator — see `FileScopeVarCollector.computedNames`.
        let computedGlobals: [String]
        let findings: [Finding]
        /// Findings whose verdict is `.pure` — the false ones.
        var falsePure: [Finding] { findings.filter { $0.verdict == .pure } }
        /// Findings the oracle already refutes for some other reason. Not a defect;
        /// reported so the population is visible rather than filtered into silence.
        var alreadyRefuted: [Finding] { findings.filter { $0.verdict != .pure } }
    }

    // MARK: - The scan

    static let results: [CorpusResult] = CorpusManifest.available.map(scan(_:))

    /// One root's parse, its file-scope `var`s split by kind, and its functions.
    private struct RootScan {
        let stored: Set<String>
        let computed: Set<String>
        var globals: Set<String> { stored.union(computed) }
        let fileCount: Int
        let functions: [(file: String, decl: FunctionDeclSyntax)]
    }

    /// Pass 1 must complete before pass 2: a write can precede its declaration's
    /// file in sort order, so collecting globals lazily would miss it.
    private static func scanRoot(_ root: URL) -> RootScan {
        var stored: Set<String> = []
        var computed: Set<String> = []
        var functions: [(file: String, decl: FunctionDeclSyntax)] = []
        var fileCount = 0
        for file in SwiftSourceFiles.sorted(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let tree = Parser.parse(source: text)
            fileCount += 1
            let collector = FileScopeVarCollector(viewMode: .sourceAccurate)
            collector.walk(tree)
            stored.formUnion(collector.storedNames)
            computed.formUnion(collector.computedNames)
            let functionCollector = CensusFunctionCollector(viewMode: .sourceAccurate)
            functionCollector.walk(tree)
            functions.append(contentsOf: functionCollector.functions.map { (file.lastPathComponent, $0) })
        }
        return RootScan(stored: stored, computed: computed, fileCount: fileCount, functions: functions)
    }

    /// Split out of the `map` closure only for the closure-body length cap; the
    /// reasoning that governs it is in this suite's header.
    private static func scan(_ corpus: CorpusManifest.Corpus) -> CorpusResult {
        var stored: Set<String> = []
        var computed: Set<String> = []
        var findings: [Finding] = []
        var fileCount = 0
        var functionCount = 0

        for root in corpus.roots {
            let scan = scanRoot(root)
            stored.formUnion(scan.stored)
            computed.formUnion(scan.computed)
            fileCount += scan.fileCount
            functionCount += scan.functions.count
            let globals = scan.globals
            guard !globals.isEmpty else { continue }
            for entry in scan.functions {
                guard let body = entry.decl.body else { continue }
                let checker = ModuleStateWriteChecker(globals: globals, viewMode: .sourceAccurate)
                checker.walk(body)
                let written = checker.written.subtracting(checker.locallyBound).sorted()
                let called = checker.memberCalled.subtracting(checker.locallyBound).sorted()
                guard !written.isEmpty || !called.isEmpty else { continue }
                findings.append(
                    Finding(
                        corpus: corpus.id,
                        root: root.lastPathComponent,
                        file: entry.file,
                        function: entry.decl.name.text,
                        written: written,
                        memberCalled: called,
                        verdict: SoundPurity.verdict(for: entry.decl)
                    )
                )
            }
        }
        return CorpusResult(
            id: corpus.id,
            files: fileCount,
            functions: functionCount,
            globals: stored.union(computed).sorted(),
            storedGlobals: stored.sorted(),
            computedGlobals: computed.sorted(),
            findings: findings
        )
    }

    static var directWrites: [Finding] {
        results.flatMap(\.falsePure).filter { !$0.written.isEmpty }
    }

    static var memberCallsOnly: [Finding] {
        results.flatMap(\.falsePure).filter { $0.written.isEmpty && !$0.memberCalled.isEmpty }
    }

    // MARK: - Controls

    /// **The universe is the manifest's, not a hand-picked trio.** The home arm's
    /// zero was measured over one package; the failure this guards is a re-take that
    /// quietly narrows back to a handful and reports a zero that means nothing.
    @Test("the arm scans the corpora the manifest resolves, not a hand-picked subset")
    func universeIsTheManifest() {
        #expect(Self.results.count >= 8, "scanned \(Self.results.count) corpora — the loader lost roots")
        #expect(
            Self.results.contains { $0.id != "swift-infer-core" },
            "a cross-corpus arm that only sees the home package is the home arm again"
        )
    }

    /// **The population is NOT zero outside this package**, which is the whole point
    /// of re-taking. If this ever goes to zero the arm has gone blind, because the
    /// home arm already proves the detector can report a true zero.
    @Test("at least one corpus declares a file-scope var, so the arm is not measuring emptiness")
    func populationIsNonEmpty() {
        let declaring = Self.results.filter { !$0.globals.isEmpty }
        #expect(
            !declaring.isEmpty,
            "no corpus declares a file-scope `var` — the collector is blind, not the corpora empty"
        )
    }

    /// **A computed `var` is not module state, and a `didSet` one is.**
    ///
    /// The first version of this arm reported "135 file-scope vars" across the
    /// corpora. 86 of them were swift-foundation's, and every one was a computed
    /// platform shim — `internal var CLOCK_REALTIME: clockid_t { … }`. The finding
    /// count was unaffected, but the *denominator* was mostly constants, and a ratio
    /// quoted off it would have been three orders of magnitude out.
    ///
    /// The obvious fix — `accessorBlock == nil` — is wrong in the flattering
    /// direction, so the `didSet` case is asserted here rather than assumed.
    @Test("the collector separates stored module state from computed globals, and observers stay stored")
    func storedAndComputedAreSeparated() {
        let tree = Parser.parse(source: """
        var storedCounter = 0
        var observed = 0 { didSet { print(observed) } }
        var computedConstant: Int { 42 }
        var computedPair: Int { get { 1 } set { } }
        """)
        let collector = FileScopeVarCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        #expect(
            collector.storedNames == ["storedCounter", "observed"],
            "stored: \(collector.storedNames.sorted()) — a `didSet` var is stored state, not a constant"
        )
        #expect(
            collector.computedNames == ["computedConstant", "computedPair"],
            "computed: \(collector.computedNames.sorted())"
        )
        #expect(collector.names.count == 4, "the union must still cover every write target")
    }

    // MARK: - The census

    @Test("census — the module-state base rate across the manifest corpora")
    func census() {
        var lines: [String] = ["", "MODULE-STATE BASE RATE — ALL MANIFEST CORPORA", ""]
        lines.append("corpora scanned: \(Self.results.count)")
        if !CorpusManifest.absent.isEmpty {
            lines.append("absent from this machine: \(CorpusManifest.absent.joined(separator: ", "))")
        }
        if !CorpusManifest.emptyRoots.isEmpty {
            lines.append("resolved but empty: \(CorpusManifest.emptyRoots.joined(separator: ", "))")
        }
        lines.append("")
        lines.append(
            "corpus                          files  funcs  stored  computed  false-pure  already-refuted"
        )
        for result in Self.results.sorted(by: { $0.id < $1.id }) {
            lines.append(
                result.id.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + String(result.files).padding(toLength: 7, withPad: " ", startingAt: 0)
                    + String(result.functions).padding(toLength: 7, withPad: " ", startingAt: 0)
                    + String(result.storedGlobals.count).padding(toLength: 8, withPad: " ", startingAt: 0)
                    + String(result.computedGlobals.count).padding(toLength: 10, withPad: " ", startingAt: 0)
                    + String(result.falsePure.count).padding(toLength: 12, withPad: " ", startingAt: 0)
                    + String(result.alreadyRefuted.count)
            )
        }
        let totalFunctions = Self.results.reduce(0) { $0 + $1.functions }
        let totalStored = Self.results.reduce(0) { $0 + $1.storedGlobals.count }
        let totalComputed = Self.results.reduce(0) { $0 + $1.computedGlobals.count }
        lines.append("")
        lines.append(
            "TOTAL functions: \(totalFunctions)   STORED file-scope vars: \(totalStored)"
                + "   (computed, not state: \(totalComputed))"
        )
        lines.append("BASE RATE — `.pure` functions writing a file-scope `var`: \(Self.directWrites.count)")
        for finding in Self.directWrites {
            let writes = finding.written.joined(separator: ", ")
            lines.append("  [\(finding.corpus)] \(finding.file):\(finding.function) -> \(writes)")
        }
        lines.append("")
        let memberCalls = Self.memberCallsOnly.count
        lines.append("unresolved surface — `.pure` functions calling a member on a global: \(memberCalls)")
        for finding in Self.memberCallsOnly.prefix(25) {
            let calls = finding.memberCalled.joined(separator: ", ")
            lines.append("  [\(finding.corpus)] \(finding.file):\(finding.function) -> \(calls)")
        }
        let refutedCount = Self.results.reduce(0) { $0 + $1.alreadyRefuted.count }
        lines.append("")
        lines.append("touching a global but ALREADY refuted (not a defect): \(refutedCount)")
        print(lines.joined(separator: "\n"))
    }
}
