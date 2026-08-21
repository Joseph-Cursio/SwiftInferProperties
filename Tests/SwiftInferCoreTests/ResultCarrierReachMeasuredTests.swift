import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **Does moving from `throws` to `Result` put more code within a law's reach?**
///
/// The claim under test, in the form people state it: *using `Result` helps
/// property-based testing, because the failure branch becomes part of the value and
/// a law can talk about it.* `docs/ideas/error-law-instrument-split.md` argues that
/// is true of laws a **human** writes. This asks the narrower, measurable question:
/// does it move anything **this tool** produces?
///
/// ## Three arms, and why the middle one is not the answer
///
/// | arm | transform | models |
/// |---|---|---|
/// | baseline | none | today |
/// | `throws` masked | `isThrows = false` | the **ceiling**: stop advertising partiality, change nothing else |
/// | `Result`-wrapped | `isThrows = false`, `T` → `Result<T, Error>` | the **actual refactor** |
///
/// The masked arm is deliberately more generous than any real refactor — it removes
/// the partiality signal without paying for it. The `Result` arm pays: the return
/// type changes, and a template that keyed on the old carrier now sees a type it may
/// not support. **A refactor can therefore score BELOW baseline**, and if it does,
/// that is the finding rather than an instrument fault.
///
/// ## What this cannot say
///
/// **Suggestion count is not law quality.** A law that fires is not a law worth
/// running — this repo's standing rule is to score refutability, not suggestions.
/// The arms bound *reach*: whether the toolchain can see the subject at all. Whether
/// the resulting laws are worth having is a separate question and is not asked here.
///
/// **The prior on this shape is a zero.** `purity-refactoring-reach.md` forced every
/// purity verdict to `.pure` — a strictly larger intervention than either arm — and
/// moved 0 of 710/160/51 suggestions, because purity is not one of
/// `UnverifiableCause`'s eight causes. *The subject throws* is not one of them
/// either. Expect a small number and be suspicious of a large one.
@Suite("Census — does a Result carrier put more code within a law's reach?", .serialized)
struct ResultCarrierReachMeasuredTests {

    struct Arm {
        let corpus: String
        let functions: Int
        let throwing: Int
        let baseline: Int
        let throwsMasked: Int
        let resultWrapped: Int
        /// Suggestions per template, baseline and `Result`-wrapped. **A net of -218
        /// is not a finding until it names the laws it removed** — the same reason
        /// the decline-cause censuses report by cause rather than by total.
        let baselineByTemplate: [String: Int]
        let wrappedByTemplate: [String: Int]
        /// Arm 4 — the same wrap, applied only to functions actually free to change
        /// signature. §4's `-66` was reached by subtracting a template total; this
        /// reaches it by not performing the illegal transform in the first place.
        let wrappedFreeOnly: Int
        /// Throwing functions whose signature is fixed by a protocol conformance.
        let conformanceFixed: Int

        var maskedDelta: Int { throwsMasked - baseline }
        var wrappedDelta: Int { resultWrapped - baseline }
        var freeOnlyDelta: Int { wrappedFreeOnly - baseline }
    }

    // MARK: - The transform

    /// The summary as it would look after `func f() throws -> T` became
    /// `func f() -> Result<T, Error>`.
    ///
    /// **A `Void`-returning throwing function becomes `Result<Void, Error>`**, not
    /// nothing — dropping those would quietly exclude the largest single shape among
    /// throwing functions and make the arm look narrower than the refactor is.
    ///
    /// Only *throwing* functions are transformed. Converting a total function to
    /// `Result` is not what anyone means by the advice, and doing it here would
    /// measure a refactor nobody proposed.
    static func withResultWrapped(_ summary: FunctionSummary) -> FunctionSummary {
        let wrapped = "Result<\(summary.returnTypeText ?? "Void"), Error>"
        return FunctionSummary(
            name: summary.name,
            parameters: summary.parameters,
            returnTypeText: wrapped,
            isThrows: false,
            isAsync: summary.isAsync,
            isMutating: summary.isMutating,
            isStatic: summary.isStatic,
            location: summary.location,
            containingTypeName: summary.containingTypeName,
            bodySignals: summary.bodySignals,
            qualifiedContainingTypeName: summary.qualifiedContainingTypeName,
            discoverableGroup: summary.discoverableGroup,
            invariantKeypath: summary.invariantKeypath,
            isInferredPure: summary.isInferredPure,
            isClockDeterministic: summary.isClockDeterministic,
            declaresUnknownEffect: summary.declaresUnknownEffect,
            isComputedProperty: summary.isComputedProperty,
            isInitializer: summary.isInitializer,
            docComment: summary.docComment,
            declaredEffect: summary.declaredEffect,
            inferredEffect: summary.inferredEffect,
            purityVerdict: summary.purityVerdict,
            bodyFingerprint: summary.bodyFingerprint,
            calledFreeFunctionNames: summary.calledFreeFunctionNames
        )
    }

    // MARK: - The scan

    /// **One root per corpus, the largest.** Several manifest entries name more than
    /// one; discovering across merged modules would let a pair form between types
    /// that cannot see each other, which inflates the baseline every arm is measured
    /// against.
    static func arm(for corpus: CorpusManifest.Corpus) throws -> Arm {
        let scanned = try FunctionScanner.scanCorpus(directory: corpus.primaryRoot)
        let summaries = scanned.summaries

        func suggestions(_ input: [FunctionSummary]) -> [Suggestion] {
            TemplateRegistry.discover(
                in: input, identities: scanned.identities, typeDecls: scanned.typeDecls
            )
        }
        func byTemplate(_ rows: [Suggestion]) -> [String: Int] {
            rows.reduce(into: [:]) { $0[$1.templateName, default: 0] += 1 }
        }

        let base = suggestions(summaries)
        let wrapped = suggestions(summaries.map { $0.isThrows ? withResultWrapped($0) : $0 })

        // Arm 4. Requirements come from two places: a built-in table for the stdlib
        // protocols a corpus conforms to without declaring, and the corpus's own
        // protocol declarations, whose bodies `FunctionScanner` deliberately skips.
        var requirements = ConformanceFixedSignatures.builtIn
        for (name, declared) in ConformanceFixedSignatures.declaredRequirements(in: corpus.primaryRoot) {
            requirements[name, default: []].formUnion(declared)
        }
        let conformances = ConformanceFixedSignatures.conformances(from: scanned.typeDecls)
        func isFixed(_ summary: FunctionSummary) -> Bool {
            ConformanceFixedSignatures.isFixed(
                summary, conformances: conformances, requirements: requirements
            )
        }
        let freeOnly = suggestions(summaries.map {
            $0.isThrows && !isFixed($0) ? withResultWrapped($0) : $0
        })

        return Arm(
            corpus: corpus.id,
            functions: summaries.count,
            throwing: summaries.filter(\.isThrows).count,
            baseline: base.count,
            throwsMasked: suggestions(summaries.map {
                $0.isThrows ? PartialPurityConsumerMeasuredTests.withThrowsMasked($0) : $0
            }).count,
            resultWrapped: wrapped.count,
            baselineByTemplate: byTemplate(base),
            wrappedByTemplate: byTemplate(wrapped),
            wrappedFreeOnly: freeOnly.count,
            conformanceFixed: summaries.filter { $0.isThrows && isFixed($0) }.count
        )
    }

    static let arms: [Arm] = CorpusManifest.available.compactMap { try? arm(for: $0) }

    // MARK: - Controls

    /// **The universe is the manifest's.** `withThrowsMasked` has been measured
    /// before — at `+2`, on item 34's *three* corpora. Re-taking it on three again
    /// would reproduce a number nobody doubted and answer nothing about generality,
    /// which is the failure two other censuses were re-taken for on 2026-08-19.
    @Test("the arm scans the corpora the manifest resolves, not a hand-picked subset")
    func universeIsTheManifest() {
        #expect(Self.arms.count >= 8, "scanned \(Self.arms.count) corpora")
        #expect(
            Self.arms.contains { $0.corpus != "swift-infer-core" },
            "a generality arm that only sees the home package is not a generality arm"
        )
    }

    /// **The population is non-empty.** Both transforms are no-ops on a corpus with
    /// no throwing functions, and a no-op arm reports 0 delta exactly like a measured
    /// zero.
    @Test("the corpora declare throwing functions, so the transforms are not no-ops")
    func populationIsNonEmpty() {
        let throwing = Self.arms.reduce(0) { $0 + $1.throwing }
        #expect(throwing > 100, "only \(throwing) throwing functions across \(Self.arms.count) corpora")
    }

    /// **The transform actually changes the summary**, asserted directly rather than
    /// inferred from a delta. A builder that silently returned its input would report
    /// a 0 delta indistinguishable from a measured one — this repo's *confident zero*,
    /// and the reason `FunctionSummary`'s field-by-field copies are worth distrusting:
    /// `withThrowsMasked` was found dropping `calledFreeFunctionNames` on 2026-08-19.
    @Test("the Result transform rewrites the return type and clears the throws flag")
    func transformFires() throws {
        let scanned = try FunctionScanner.scanCorpus(
            directory: PurityRefutationCensusMeasuredTests.packageSourcesRoot
        )
        // Bound outside the macro: a key-path `where:` reads as `rethrows` inside
        // `#require`'s expansion, and the outer `try` does not cover it.
        let firstThrowing = scanned.summaries.first(where: \.isThrows)
        let throwing = try #require(firstThrowing)
        let wrapped = Self.withResultWrapped(throwing)

        #expect(wrapped.isThrows == false)
        #expect(wrapped.returnTypeText?.hasPrefix("Result<") == true, "got \(wrapped.returnTypeText ?? "nil")")
        #expect(
            wrapped.calledFreeFunctionNames == throwing.calledFreeFunctionNames,
            "the copy dropped a field; every arm downstream is now measuring the drop"
        )
    }

    /// **A name alone must not classify a signature as fixed.**
    ///
    /// The cheap classifier — *anything called `encode` is a `Codable` requirement* —
    /// is the shape `purity-refuting-fixpoint-census.md` refuted: 46 of 75 cascade
    /// rows were `classify`-style name collisions, **61% false**. This asserts both
    /// directions on one synthetic file, because a classifier that fires on
    /// everything and one that fires on nothing both produce a tidy number.
    @Test("a conformance-fixed signature needs the conformance, not just the name")
    func nameAloneIsNotEnough() throws {
        let source = """
        struct Conforming: Codable {
            func encode(to encoder: any Encoder) throws {}
        }
        struct Unlucky {
            func encode(to sink: Sink) throws {}
        }
        protocol Loader {
            func load(from path: String) throws -> Data
        }
        struct Impl: Loader {
            func load(from path: String) throws -> Data { Data() }
        }
        """
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("conformance-fixed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try source.write(
            to: directory.appendingPathComponent("Subject.swift"), atomically: true, encoding: .utf8
        )

        let scanned = try FunctionScanner.scanCorpus(directory: directory)
        var requirements = ConformanceFixedSignatures.builtIn
        for (name, declared) in ConformanceFixedSignatures.declaredRequirements(in: directory) {
            requirements[name, default: []].formUnion(declared)
        }
        let conformances = ConformanceFixedSignatures.conformances(from: scanned.typeDecls)
        func fixed(_ owner: String, _ name: String) throws -> Bool {
            let match = scanned.summaries.first {
                $0.containingTypeName == owner && $0.name == name
            }
            let summary = try #require(match, "no summary for \(owner).\(name)")
            return ConformanceFixedSignatures.isFixed(
                summary, conformances: conformances, requirements: requirements
            )
        }

        #expect(try fixed("Conforming", "encode"), "a Codable type's encode(to:) is fixed")
        #expect(
            try fixed("Unlucky", "encode") == false,
            "an identically-named method on a non-conforming type is FREE — this is the 61% case"
        )
        #expect(
            try fixed("Impl", "load"),
            "a corpus-declared protocol's throwing requirement is fixed too, not just the stdlib's"
        )
    }

    /// **The classifier finds a population on the real corpora.** A structural rule
    /// that silently matches nothing reports the same arm-4 number as one that has
    /// nothing to match, and only this separates them.
    @Test("the classifier finds conformance-fixed signatures across the corpora")
    func classifierFindsAPopulation() {
        let fixed = Self.arms.reduce(0) { $0 + $1.conformanceFixed }
        #expect(fixed > 20, "only \(fixed) conformance-fixed throwing functions found")
    }

    // MARK: - The census

    @Test("census — throws-masked and Result-wrapped reach, across the manifest corpora")
    func census() {
        var lines: [String] = ["", "RESULT-CARRIER REACH — ALL MANIFEST CORPORA", ""]
        lines.append("corpus                          funcs  throwing  baseline  masked(Δ)   Result(Δ)")
        for arm in Self.arms.sorted(by: { $0.corpus < $1.corpus }) {
            lines.append(
                arm.corpus.padding(toLength: 32, withPad: " ", startingAt: 0)
                    + String(arm.functions).padding(toLength: 7, withPad: " ", startingAt: 0)
                    + String(arm.throwing).padding(toLength: 10, withPad: " ", startingAt: 0)
                    + String(arm.baseline).padding(toLength: 10, withPad: " ", startingAt: 0)
                    + "\(arm.throwsMasked) (\(arm.maskedDelta >= 0 ? "+" : "")\(arm.maskedDelta))"
                        .padding(toLength: 12, withPad: " ", startingAt: 0)
                    + "\(arm.resultWrapped) (\(arm.wrappedDelta >= 0 ? "+" : "")\(arm.wrappedDelta))"
            )
        }
        let functions = Self.arms.reduce(0) { $0 + $1.functions }
        let throwing = Self.arms.reduce(0) { $0 + $1.throwing }
        let baseline = Self.arms.reduce(0) { $0 + $1.baseline }
        let masked = Self.arms.reduce(0) { $0 + $1.maskedDelta }
        let wrapped = Self.arms.reduce(0) { $0 + $1.wrappedDelta }
        lines.append("")
        lines.append("TOTAL  functions \(functions) · throwing \(throwing) · baseline suggestions \(baseline)")
        lines.append("CEILING  (throws masked):   \(masked >= 0 ? "+" : "")\(masked)")
        lines.append("REFACTOR (Result-wrapped):  \(wrapped >= 0 ? "+" : "")\(wrapped)")
        let freeOnly = Self.arms.reduce(0) { $0 + $1.freeOnlyDelta }
        let fixed = Self.arms.reduce(0) { $0 + $1.conformanceFixed }
        lines.append("PERFORMABLE (free signatures only): \(freeOnly >= 0 ? "+" : "")\(freeOnly)")
        lines.append("  conformance-fixed throwing functions skipped: \(fixed)")
        lines.append("  §4 reached ~-66 by subtracting a template total; this is the measured figure")

        // Which laws the refactor removes. A net figure hides whether the loss is one
        // template collapsing or every template shedding a row, and those are
        // different findings.
        var deltaByTemplate: [String: Int] = [:]
        for arm in Self.arms {
            for (template, count) in arm.baselineByTemplate {
                deltaByTemplate[template, default: 0] -= count
            }
            for (template, count) in arm.wrappedByTemplate {
                deltaByTemplate[template, default: 0] += count
            }
        }
        lines.append("")
        lines.append("WHERE THE REFACTOR'S LOSS LANDS, by template:")
        for (template, delta) in deltaByTemplate.filter({ $0.value != 0 }).sorted(by: { $0.value < $1.value }) {
            lines.append("  \(template): \(delta)")
        }
        let untouched = deltaByTemplate.filter { $0.value == 0 }.map(\.key).sorted()
        lines.append("  (unchanged: \(untouched.joined(separator: ", ")))")
        print(lines.joined(separator: "\n"))
    }
}
