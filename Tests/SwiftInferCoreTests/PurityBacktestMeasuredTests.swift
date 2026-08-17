import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **Phase 0.6 of `docs/plans/declaration-claims-plan.md`: does the purity oracle
/// flag a real historical purity bug, and not its fix?**
///
/// Every other measurement in this repo grades the tool with the tool — this corpus,
/// this binary, the instrument CLAUDE.md calls contaminable (*a tool may not grade
/// its own homework*). A backtest is a different instrument: **the oracle is a public
/// fix commit that predates these tools**, cannot be influenced by them, and survives
/// churn. It is the only arm here producing a number defensible outside the repo.
///
/// ## Method
///
/// Mine third-party history for fix commits whose bug *was* a purity failure — a
/// hidden clock read, a value that varies run to run, a method mutating shared state.
/// Take the declaration as it stood at `<fix>^` and as it stands at `<fix>`, and ask
/// `SoundPurity.verdict(for:)` about both.
///
/// | reading | meaning |
/// |---|---|
/// | **HIT** | pre-fix refuted, post-fix pure — the tool saw the bug and not the fix |
/// | **MISS** | pre-fix `.pure` — the tool cannot see this bug class |
/// | **FALSE ALARM** | post-fix refuted — the tool objects to correct code |
///
/// ## The sources are frozen here rather than read from sibling checkouts
///
/// Each case carries its declaration verbatim with the SHA it came from. That keeps
/// the suite runnable in `make batch2` on a machine with none of these repos cloned,
/// and it makes the case a **fixture the oracle is re-run against on every commit**
/// rather than a number in a document. The cost is that a fixture can drift from the
/// commit it claims to quote; the SHA is recorded so it can be checked, and
/// `docs/measurements/purity-backtest.md` carries the extraction commands.
///
/// **Backtest at `<fix>^`, never `HEAD`.** These libraries are correct at `HEAD`, so
/// an all-green run there cannot be told from a blind tool — the rule
/// `kit-suite-backtest-plan.md` records, applied here.
@Suite("Backtest — does the purity oracle flag real historical purity bugs?", .serialized)
struct PurityBacktestMeasuredTests {

    struct Case {
        let name: String
        let provenance: String
        /// What actually went wrong, in the terms the fix commit used.
        let bug: String
        let pre: String
        let post: String
    }

    /// **Case 1 — SwiftLint `006bb2a8` (#3823), "Sort implicit return configuration
    /// description".** `includedKinds` is a `Set`, so `.map { $0.rawValue }` yields
    /// its elements in *hash-seed order* and `joined` renders a different string run
    /// to run. The fix inserts `.sorted()`.
    ///
    /// The same defect this repo hit in `CrossFileVisitorBase.orderedSources`, where
    /// a dictionary's value order made a reported hop count *a coin flip*. A public
    /// instance of a bug class the toolchain has already paid for.
    static let setOrderInConsoleDescription = Case(
        name: "SwiftLint consoleDescription — Set order",
        provenance: "SwiftLint@006bb2a85, ImplicitReturnConfiguration.swift",
        bug: "a Set's iteration order rendered into a String; output differed run to run",
        pre: """
        public var consoleDescription: String {
            let includedKinds = self.includedKinds.map { $0.rawValue }
            return severityConfiguration.consoleDescription +
                ", included: [\\(includedKinds.joined(separator: ", "))]"
        }
        """,
        post: """
        public var consoleDescription: String {
            let includedKinds = self.includedKinds.map { $0.rawValue }
            return severityConfiguration.consoleDescription +
                ", included: [\\(includedKinds.sorted().joined(separator: ", "))]"
        }
        """
    )

    /// **Case 2 — SwiftLint `0c095204`, "ensure deterministic consoleDescription &
    /// cacheDescription generation".** Same bug class, found again across three
    /// configuration types. Kept as a separate case because a bug class that recurs
    /// in one repository is evidence about the class, not a duplicate.
    static let setOrderInAttributes = Case(
        name: "SwiftLint attributes consoleDescription — Set order",
        provenance: "SwiftLint@0c0952046, AttributesConfiguration.swift",
        bug: "two Sets interpolated directly; the cache key they fed differed run to run",
        pre: """
        public var consoleDescription: String {
            return severityConfiguration.consoleDescription +
                ", always_on_same_line: \\(alwaysOnSameLine)" +
                ", always_on_line_above: \\(alwaysOnNewLine)"
        }
        """,
        post: """
        public var consoleDescription: String {
            return severityConfiguration.consoleDescription +
                ", always_on_same_line: \\(alwaysOnSameLine.sorted())" +
                ", always_on_line_above: \\(alwaysOnNewLine.sorted())"
        }
        """
    )

    /// **Case 3 — Harmonize `a8abcfa` (#39), "Fix scope cache interaction bug".** A
    /// builder on a **class** whose methods assigned to `self` and returned it, so two
    /// scopes built from one builder shared state and collided on a cache key. The fix
    /// returns a copy.
    ///
    /// The plan names this shape directly: *a function that mutated shared state
    /// through a captured reference*. On a `class` there is no `mutating` keyword to
    /// give it away — which is exactly why an oracle is wanted.
    static let builderMutatesSelf = Case(
        name: "Harmonize builder — mutates self, returns self",
        provenance: "Harmonize@a8abcfa, HarmonizeScopeBuilder.swift (internal class)",
        bug: "builder methods mutated shared reference state; two scopes collided on a cache key",
        pre: """
        func excluding(_ excludes: [String]) -> HarmonizeScope {
            self.exclusions = excludes + exclusions
            return self
        }
        """,
        post: """
        func excluding(_ excludes: [String]) -> HarmonizeScope {
            return self.copy(exclusions: excludes + self.exclusions)
        }
        """
    )

    static let cases: [Case] = [setOrderInConsoleDescription, setOrderInAttributes, builderMutatesSelf]

    // MARK: - The oracle

    /// The verdict for the first declaration in `source` — function or computed
    /// property, since two of the three cases are the latter and a backtest that
    /// silently skipped them would be reporting on a population it chose.
    static func verdict(of source: String) -> PurityVerdict? {
        let tree = Parser.parse(source: "struct Harness {\n\(source)\n}")
        let finder = BacktestDeclarationFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        if let function = finder.functions.first { return SoundPurity.verdict(for: function) }
        if let accessor = finder.accessors.first {
            return PurityInferrer().isPure(accessor) ? .pure : .refuted
        }
        return nil
    }

    struct Reading {
        let name: String
        let pre: PurityVerdict?
        let post: PurityVerdict?

        /// A hit needs **both** halves: seeing the bug is worth nothing if the tool
        /// also objects to the fix, which would make it a rule that dislikes the
        /// shape rather than an oracle that detects the defect.
        var isHit: Bool { pre == .refuted && post == .pure }
        var isFalseAlarm: Bool { post == .refuted }
    }

    static let readings: [Reading] = cases.map {
        Reading(name: $0.name, pre: verdict(of: $0.pre), post: verdict(of: $0.post))
    }

    // MARK: - Controls

    /// **Every case parses and yields a verdict.** A `nil` would make its row
    /// unreadable, and a backtest whose cases silently failed to parse would report
    /// all-MISS — indistinguishable from a blind tool, which is the reading this arm
    /// exists to rule out.
    @Test("every backtest case parses to a verdict on both sides")
    func everyCaseYieldsAVerdict() {
        for reading in Self.readings {
            #expect(reading.pre != nil, "\(reading.name): pre-fix source did not yield a verdict")
            #expect(reading.post != nil, "\(reading.name): post-fix source did not yield a verdict")
        }
    }

    /// The oracle is running: a declaration with a marker in it must refute, through
    /// the same entry point the cases use.
    @Test("the harness's oracle refutes a known impurity")
    func harnessOracleIsLive() {
        #expect(Self.verdict(of: "func f(_ text: String) -> Int { print(text); return 1 }") == .refuted)
        #expect(Self.verdict(of: "func f(_ value: Int) -> Int { value + 1 }") == .pure)
    }

    /// **No false alarms.** The tool objecting to corrected code is worse than
    /// missing the bug: a miss is silence, an objection is advice to undo a fix.
    @Test("the tool does not object to any post-fix declaration")
    func noFalseAlarms() {
        let alarms = Self.readings.filter(\.isFalseAlarm).map(\.name)
        #expect(alarms.isEmpty, "the tool refutes corrected code: \(alarms)")
    }

    /// **Where the state-mutation boundary actually is**, measured because case 3's
    /// MISS is only interesting if it is not an artifact of this harness's wrapper.
    ///
    /// It is not: the verdict is identical whether the method is wrapped in a
    /// `struct`, a `class`, or nothing at all. What decides it is the *spelling of the
    /// receiver*:
    ///
    /// | write | verdict | |
    /// |---|---|---|
    /// | `Self.y = x` — static | `.refuted` | `ReducerPurityAnalyzer` |
    /// | `self.y = x` — instance, **class** | **`.pure`** | nothing — shared reference state |
    /// | `self.y = x` — instance, `mutating` struct | `.pure` | defensible: value semantics, and `mutating` says so |
    /// | file-scope `var` | `.pure` | nothing — but base rate 0 here |
    ///
    /// **The class row is the defect.** A non-`mutating` method writing `self` on a
    /// reference type mutates state every holder of that reference can see, which is
    /// what the Harmonize bug was. The struct row is not a defect — a `mutating`
    /// method mutates a copy, and Swift makes the caller opt in.
    ///
    /// So `docs/measurements/module-state-base-rate.md`'s zero was narrower than the
    /// gap: file-scope `var`s are absent from that corpus, but classes with mutable
    /// state are not rare anywhere. **That base rate is unmeasured and is filed, not
    /// built on.**
    @Test("the state-mutation boundary is the receiver's spelling, not the harness wrapper")
    func stateMutationBoundary() {
        let instanceWrite = "func f(_ value: Int) -> Int { self.stored = value; return value }"
        #expect(Self.verdict(of: instanceWrite) == .pure, "instance `self` write is refuted now — re-take the backtest")

        let staticWrite = "func f(_ value: Int) -> Int { Self.stored = value; return value }"
        #expect(Self.verdict(of: staticWrite) == .refuted, "ReducerPurityAnalyzer's static clause has regressed")
    }

    // MARK: - The census

    @Test("backtest — pre-fix versus post-fix, case by case")
    func backtest() {
        var lines: [String] = ["", "PURITY BACKTEST", ""]
        for (index, subject) in Self.cases.enumerated() {
            let reading = Self.readings[index]
            let outcome = reading.isHit ? "HIT" : (reading.isFalseAlarm ? "FALSE ALARM" : "MISS")
            lines.append("[\(outcome)] \(subject.name)")
            lines.append("    provenance: \(subject.provenance)")
            lines.append("    bug:        \(subject.bug)")
            lines.append("    pre-fix:    \(reading.pre.map { "\($0)" } ?? "nil")")
            lines.append("    post-fix:   \(reading.post.map { "\($0)" } ?? "nil")")
        }
        let hits = Self.readings.filter(\.isHit).count
        lines.append("")
        lines.append("HITS: \(hits) of \(Self.readings.count)")
        print(lines.joined(separator: "\n"))
    }
}

/// Function declarations and accessor blocks, so a computed property is reachable
/// through the same probe as a function.
private final class BacktestDeclarationFinder: SyntaxVisitor {
    private(set) var functions: [FunctionDeclSyntax] = []
    private(set) var accessors: [AccessorBlockSyntax] = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functions.append(node)
        return .visitChildren
    }

    override func visit(_ node: AccessorBlockSyntax) -> SyntaxVisitorContinueKind {
        accessors.append(node)
        return .visitChildren
    }
}
