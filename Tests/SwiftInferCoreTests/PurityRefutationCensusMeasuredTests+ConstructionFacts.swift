import Foundation
import SwiftEffectInference
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **What the construction table moved on `Sources/` — configured against unconfigured, on the
/// SAME trees.**
///
/// The facts-only delta. Comparing against an earlier run would mix it with every line of new
/// code the wiring itself added to `Sources/`, so both arms here judge one parse: the configured
/// oracle `CensusPurity` builds, and `SoundPurity.unconfigured` over the identical nodes. The
/// absolute totals are the census above; this is the difference the table alone makes.
///
/// The `construction` tally a row here prints is a **lower bound** (see
/// `RefutationCause.construction`); the flips, the re-witnessed rows and the split are exact.
extension PurityRefutationCensusMeasuredTests {

    /// The two arms' function verdicts and SEI first witnesses, aligned with `corpus`.
    struct FactsArms {
        let unconfiguredVerdicts: [PurityVerdict]
        let flipped: [String]
        let rewitnessed: [String]
        let unconfiguredSplit: (witness: Int, ignorance: Int)
    }

    static let factsArms: FactsArms = {
        let unconfigured = SoundPurity.unconfigured
        let verdictsWithout = corpus.map { unconfigured.verdict(for: $0.function) }
        var flipped: [String] = []
        var rewitnessed: [String] = []
        for (index, subject) in corpus.enumerated() {
            let label = "\(subject.file):\(subject.name)"
            if verdictsWithout[index] != verdicts[index] {
                flipped.append("\(label) \(verdictsWithout[index]) → \(verdicts[index])")
            }
            let before = unconfigured.inferrerRefutation(for: subject.function)
            let after = CensusPurity.oracle.inferrerRefutation(for: subject.function)
            if before != after {
                rewitnessed.append("\(label): \(before?.description ?? "none") → \(after?.description ?? "none")")
            }
        }
        let blind = Attributor(inferrer: PurityInferrer())
        let refutedWithout = zip(corpus, verdictsWithout).filter { $0.1 == .refuted }
        let witness = refutedWithout.filter { blind.causes(of: $0.0.function).contains(where: \.isWitness) }.count
        return FactsArms(
            unconfiguredVerdicts: verdictsWithout,
            flipped: flipped,
            rewitnessed: rewitnessed,
            unconfiguredSplit: (witness, refutedWithout.count - witness)
        )
    }()

    struct AccessorAndClosureFlips {
        var accessors = 0
        var accessorFlips: [String] = []
        var closures = 0
        var closureFlips: [String] = []
    }

    /// Accessor blocks and closure literals, both arms, over the same trees.
    static func accessorAndClosureFlips() -> AccessorAndClosureFlips {
        let configured = CensusPurity.inferrer
        let unconfigured = PurityInferrer()
        var flips = AccessorAndClosureFlips()
        for file in SwiftSourceFiles.sorted(in: packageSourcesRoot) {
            guard let tree = CensusPurity.tree(for: file) else { continue }
            let properties = CensusFunctionCollector(viewMode: .sourceAccurate)
            properties.walk(tree)
            for (name, accessor) in properties.accessorsByName {
                flips.accessors += 1
                if configured.isPure(accessor) != unconfigured.isPure(accessor) {
                    flips.accessorFlips.append("\(file.lastPathComponent)#\(name)")
                }
            }
            let passed = CensusClosureArgumentCollector(viewMode: .sourceAccurate)
            passed.walk(tree)
            for argument in passed.passed {
                flips.closures += 1
                if configured.isPure(argument.closure) != unconfigured.isPure(argument.closure) {
                    flips.closureFlips.append("\(file.lastPathComponent):\(argument.calleeName)")
                }
            }
        }
        return flips
    }

    /// **The table only refutes.** SEI builds it monotone and the inferrer consults it as one
    /// more refuter, so no row may move toward `.pure` — a promotion would mean the configured
    /// arm is not a superset of the unconfigured one, which is the soundness claim itself.
    @Test("the construction table never promotes a verdict on Sources/")
    func constructionFactsNeverPromote() {
        let promoted = zip(Self.factsArms.unconfiguredVerdicts, Self.verdicts).filter { before, after in
            before == .refuted && after != .refuted || before == .pureButPartial && after == .pure
        }
        #expect(promoted.isEmpty, "\(promoted.count) verdicts moved TOWARD pure under the table")
    }

    @Test("census — what the construction table moves on Sources/, on the same trees")
    func constructionFactsCensus() throws {
        let arms = Self.factsArms
        let package = CensusPurity.ownPackage
        let other = Self.accessorAndClosureFlips()
        let joined = try FunctionScanner.scanCorpus(directory: Self.packageSourcesRoot, purity: package).summaries
        let joinedWithout = try FunctionScanner.scanCorpus(
            directory: Self.packageSourcesRoot, purity: package.withoutConstructionFacts
        ).summaries
        let pure = { (rows: [FunctionSummary]) in rows.filter(\.isInferredPure).count }
        let byVerdict = { (verdicts: [PurityVerdict]) in
            let counts = [PurityVerdict.pure, .pureButPartial, .refuted].map { verdict in
                "\(verdict) \(verdicts.filter { $0 == verdict }.count)"
            }
            return counts.joined(separator: " · ")
        }
        let before = arms.unconfiguredSplit
        let constructionRows = Self.refuted.filter { $0.causes.contains(.construction) }.count
        var lines = [
            "universe: \(package.universe.count) files under \(package.root?.lastPathComponent ?? "?")",
            "refuted types (\(package.refutedTypes.count)):"
        ]
        lines += package.refutedTypes.map { "  \($0)" }
        lines += [
            "functions (\(Self.corpus.count)), unconfigured: \(byVerdict(arms.unconfiguredVerdicts))",
            "functions (\(Self.corpus.count)), configured:   \(byVerdict(Self.verdicts))",
            "function verdict flips: \(arms.flipped.count)"
        ]
        lines += arms.flipped.map { "  \($0)" }
        lines.append("re-witnessed (SEI first witness changed): \(arms.rewitnessed.count)")
        lines += arms.rewitnessed.map { "  \($0)" }
        lines += [
            "split, unconfigured: witness-bearing \(before.witness) · ignorance-only \(before.ignorance)",
            "split, configured:   witness-bearing \(Self.split.witnessBearing) · ignorance-only "
                + "\(Self.split.ignoranceOnly)",
            "construction cause (LOWER BOUND): \(constructionRows)",
            "accessor blocks: \(other.accessors), flips \(other.accessorFlips.count) \(other.accessorFlips)",
            "closure literals passed at a call: \(other.closures), flips \(other.closureFlips.count) "
                + "\(other.closureFlips)",
            "summaries, join applied: \(joined.count) · .pure \(pure(joinedWithout)) → \(pure(joined))"
        ]
        print(lines.joined(separator: "\n"))
    }
}
