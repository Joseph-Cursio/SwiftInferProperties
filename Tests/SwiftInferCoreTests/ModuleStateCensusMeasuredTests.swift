import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **How many `.pure` verdicts belong to a function that mutates module state?**
///
/// The base rate for the asymmetry `docs/measurements/ownership-premise-declined.md`
/// turned up while probing something else:
///
/// | shape | verdict | refuted by |
/// |---|---|---|
/// | `S.total += value` — static member | `.refuted` | `ReducerPurityAnalyzer` |
/// | `counter += value` — **file-scope `var`** | **`.pure`** | **nothing** |
/// | `{ counter += 1 }` — closure capture | refuted | `refuteIfCaptured` |
///
/// The same write is refuted inside a closure and admitted inside a function, and
/// nothing in `verdict(for:)` looks outside the body's own tokens. **That census
/// deliberately did not measure how often it happens here**, because it is a
/// different query and folding it in would have implied coverage it did not have.
/// This is that query.
///
/// ## What the number decides
///
/// Item 40's shape is the precedent: an unchecked claim whose base rate measured
/// **zero**, reported as a latent unsoundness rather than a defect. If this measures
/// zero, the asymmetry is real and theoretical, and the honest close is that the
/// function path's missing refuter costs this corpus nothing. If it does not, every
/// row is a **false `.pure`** — the direction SEI's own doc calls the most dangerous
/// place to land wrongly, because a generated property test runs the function
/// in-process over random inputs.
///
/// ## Scope, and why it is narrower than "global state"
///
/// **`var` declared at file scope only.** `static` and `Self` writes are already
/// refuted by `ReducerPurityAnalyzer` — the `reducerEffect` cause's 26 rows — so
/// including them would double-count a covered case. A `let` cannot be mutated.
///
/// **Grouped by target, not module-wide.** A file-scope `var` is `internal`, so it is
/// visible across its own module and not beyond. Matching a body against every
/// target's globals at once would over-count; matching within `Sources/<Target>/`
/// is the closest cheap approximation of Swift's actual visibility.
///
/// **Shadowing is honoured.** A local `var counter` or a parameter of that name binds
/// the write locally, and locals are not state. Without this the census counts every
/// function that happens to reuse a global's name.
@Suite("Census — how often is a module-state mutation judged pure?", .serialized)
struct ModuleStateCensusMeasuredTests {

    typealias Subject = PurityRefutationCensusMeasuredTests.Subject

    // MARK: - The globals

    /// File-scope `var` names, keyed by the target directory that owns them.
    ///
    /// Read from the same file enumeration the item 29 census uses, so the two
    /// documents share a denominator rather than each walking `Sources/` its own way.
    static let globalsByTarget: [String: Set<String>] = {
        var table: [String: Set<String>] = [:]
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        for file in SwiftSourceFiles.sorted(in: root) {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
            let target = relative.split(separator: "/").first.map(String.init) ?? relative
            let collector = FileScopeVarCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: text))
            if !collector.names.isEmpty {
                table[target, default: []].formUnion(collector.names)
            }
        }
        return table
    }()

    /// The target a subject's file belongs to — `Sources/<Target>/…`.
    static func target(of subject: Subject) -> String {
        let stripped = subject.file.replacingOccurrences(of: "Sources/", with: "")
        return stripped.split(separator: "/").first.map(String.init) ?? stripped
    }

    // MARK: - The population

    struct Hit {
        let subject: Subject
        let written: [String]
        let memberCalled: [String]
    }

    /// `.pure` subjects whose body touches a file-scope `var` of their own target.
    ///
    /// Split into two buckets because their confidence differs and averaging them
    /// would hide that — see `directWrites` and `memberCalls` below.
    static let hits: [Hit] = {
        zip(
            PurityRefutationCensusMeasuredTests.corpus,
            PurityRefutationCensusMeasuredTests.verdicts
        )
        .filter { $0.1 == .pure }
        .compactMap { subject, _ -> Hit? in
            guard let body = subject.function.body else { return nil }
            let globals = globalsByTarget[target(of: subject)] ?? []
            guard !globals.isEmpty else { return nil }
            let checker = ModuleStateWriteChecker(globals: globals, viewMode: .sourceAccurate)
            checker.walk(body)
            let written = checker.written.subtracting(checker.locallyBound).sorted()
            let called = checker.memberCalled.subtracting(checker.locallyBound).sorted()
            if written.isEmpty, called.isEmpty { return nil }
            return Hit(subject: subject, written: written, memberCalled: called)
        }
    }()

    /// **The usable number.** A direct assignment, compound assignment or `&`
    /// pass-through to a file-scope `var`. Unambiguously a write.
    static let directWrites: [Hit] = hits.filter { !$0.written.isEmpty }

    /// Lower confidence, reported separately and **not** added to the above. A
    /// member call on a global — `cache.append(x)` mutates, `cache.count` does not,
    /// and this census cannot tell them apart without resolving the method. Counted
    /// so the unresolved surface is visible rather than silently omitted.
    static let memberCalls: [Hit] = hits.filter { $0.written.isEmpty && !$0.memberCalled.isEmpty }

    // MARK: - Controls

    /// **The instrument fires.** Without this, a base rate of zero cannot be told
    /// from a detector that never matches — which is the failure mode item 33's
    /// zero turned out to be, and the one this repo names *a zero measured with a
    /// blind instrument is not a zero*.
    @Test("the write detector fires on a synthetic module-state mutation")
    func detectorFires() {
        let tree = Parser.parse(source: """
        var counter = 0
        var log: [String] = []

        func bump(_ value: Int) -> Int {
            counter += value
            return counter
        }

        func shadowed(_ value: Int) -> Int {
            var counter = 0
            counter += value
            return counter
        }
        """)
        let finder = ModuleStateFunctionFinder(viewMode: .sourceAccurate)
        finder.walk(tree)

        let bump = finder.found.first { $0.name.text == "bump" }
        let shadowed = finder.found.first { $0.name.text == "shadowed" }

        #expect(Self.writes(in: bump, globals: ["counter", "log"]) == ["counter"])
        #expect(
            Self.writes(in: shadowed, globals: ["counter", "log"]).isEmpty,
            "a local `var counter` shadows the global; the write is to a local and is not state"
        )
    }

    /// **The collector finds file-scope `var`s when they exist** — asserted on a
    /// synthetic witness, because on the real corpus it finds none and a collector
    /// that never fires would report the same zero.
    @Test("the file-scope collector fires, and ignores static and local vars")
    func collectorFires() {
        let tree = Parser.parse(source: """
        var moduleCounter = 0
        let moduleConstant = 1
        struct S { static var total = 0 }
        func f() { var local = 0; local += 1 }
        """)
        let collector = FileScopeVarCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        #expect(collector.names == ["moduleCounter"], "found \(collector.names.sorted())")
    }

    /// **This corpus declares ZERO file-scope `var`s, and that is the finding.**
    ///
    /// Pinned rather than asserted as a precondition: a zero population is the answer
    /// to the base-rate question, not an obstacle to asking it. Independently
    /// corroborated by `grep -c '^var ' Sources/`, which is also 0 — worth having,
    /// because a collector bug and an empty corpus produce identical output and
    /// `collectorFires` alone cannot separate them on this tree.
    ///
    /// **It fails the day a module-level `var` lands**, which is the notification that
    /// matters: at that moment the asymmetry stops being theoretical and this census
    /// must be re-taken.
    @Test("the corpus declares no file-scope vars, so the base rate is structurally 0")
    func corpusHasNoModuleState() {
        let total = Self.globalsByTarget.values.reduce(0) { $0 + $1.count }
        #expect(
            total == 0,
            "a file-scope `var` appeared in Sources/ — \(Self.globalsByTarget) — re-take this census"
        )
        #expect(Self.directWrites.isEmpty)
        #expect(Self.memberCalls.isEmpty)
    }

    /// Every hit is `.pure` by construction, so each one is a false verdict rather
    /// than a finding about a function already refuted.
    @Test("every hit is a .pure verdict, so every hit is a false one")
    func everyHitIsPure() {
        let allPure = Self.hits.allSatisfy {
            SoundPurity.verdict(for: $0.subject.function) == .pure
        }
        #expect(allPure, "a non-`.pure` subject reached the hit list; the population filter is wrong")
    }

    static func writes(in function: FunctionDeclSyntax?, globals: Set<String>) -> [String] {
        guard let body = function?.body else { return [] }
        let checker = ModuleStateWriteChecker(globals: globals, viewMode: .sourceAccurate)
        checker.walk(body)
        return checker.written.subtracting(checker.locallyBound).sorted()
    }

    // MARK: - The census

    @Test("census — the module-state base rate")
    func census() {
        let pureCount = PurityRefutationCensusMeasuredTests.verdicts.filter { $0 == .pure }.count
        var lines: [String] = ["", "MODULE-STATE BASE RATE CENSUS", ""]
        lines.append("corpus: \(PurityRefutationCensusMeasuredTests.corpus.count) functions, \(pureCount) `.pure`")
        lines.append("file-scope `var` declarations, by target:")
        for (target, names) in Self.globalsByTarget.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(target): \(names.count) — \(names.sorted().prefix(8).joined(separator: ", "))")
        }
        lines.append("")
        lines.append("BASE RATE — `.pure` functions writing a file-scope `var`: \(Self.directWrites.count)")
        for hit in Self.directWrites {
            let file = hit.subject.file.replacingOccurrences(of: "Sources/", with: "")
            lines.append("  \(file):\(hit.subject.name) -> \(hit.written.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("unresolved surface — `.pure` functions calling a member on a global: \(Self.memberCalls.count)")
        for hit in Self.memberCalls.prefix(20) {
            let file = hit.subject.file.replacingOccurrences(of: "Sources/", with: "")
            lines.append("  \(file):\(hit.subject.name) -> \(hit.memberCalled.joined(separator: ", "))")
        }
        print(lines.joined(separator: "\n"))
    }
}
