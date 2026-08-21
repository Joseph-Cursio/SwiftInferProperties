import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// The computed-property half of the census. It reaches the same `.refuted`
/// bucket by a different route — `makeSummary(fromComputedProperty:)` rather
/// than `makeSummary(from:)` — and that route is where the census found its
/// largest single distortion. Split from the main suite because it is a
/// different population, not because of the line cap.
extension PurityRefutationCensusMeasuredTests {

    /// **A third population is in the bucket that neither half of the taxonomy
    /// described — verdicts nobody computed — and it is now FIXED, so this test
    /// pins the repair rather than the defect.**
    ///
    /// As measured: `makeSummary(fromComputedProperty:)` passed no
    /// `purityVerdict`, so all 180 read-only computed properties under `Sources/`
    /// took `FunctionSummary.init`'s `.refuted` default — while being handed
    /// `isInferredPure: true` unconditionally, which the field's own doc says is
    /// impossible (*"`isInferredPure` is `purityVerdict == .pure`"*). The bucket a
    /// consumer saw was 464 rather than 284, 39% of it a question never asked.
    ///
    /// Fixed 2026-08-17 by `SoundPurity.verdict(forGetter:)`, and **0 advisory
    /// rows moved**: neither refuter fires on any of the 180, so the constant had
    /// been accidentally correct on this corpus the whole time.
    ///
    /// What this test now guards is that the answer stays *computed*. Asserting
    /// "all 180 are `.pure`" would pass just as well against a constant `true`,
    /// which is the shape being repaired — so the assertion is the **invariant**
    /// (`isInferredPure == (purityVerdict == .pure)`, over the real corpus), and
    /// the oracle's teeth are pinned separately by
    /// `PurityVerdictAdoptionTests.clockReadingGetterIsRefuted`.
    /// Getters this repo's own oracle refutes for a reason that is not a defect. See the
    /// comment at the assertion site — all three are the token `shuffled` appearing as an
    /// enum case name rather than as a call.
    static let knownFalseRefutations: Set<String> = [
        "RolePostcondition.swift#law",
        "RolePostcondition.swift#isStrong",
        "RolePostcondition.swift#permittedLabels"
    ]

    @Test("every computed property carries a verdict its Bool agrees with")
    func computedPropertiesCarryARealVerdict() throws {
        let summaries = try FunctionScanner.scan(directory: Self.packageSourcesRoot)
        let computed = summaries.filter(\.isComputedProperty)
        #expect(!computed.isEmpty)
        let brokenInvariant = computed.filter { $0.isInferredPure != ($0.purityVerdict == .pure) }
        #expect(
            brokenInvariant.isEmpty,
            """
            \(brokenInvariant.count) computed properties claim purity and a verdict that \
            disagree — the defect this test was written for: \
            \(brokenInvariant.prefix(5).map(\.name).joined(separator: ", "))
            """
        )
    }

    /// **The A/B that made the repair a no-op, kept as a standing measurement.**
    /// `PurityInferrer.isPure(_ accessor:)` is the oracle a getter should be put
    /// through; before the fix it existed and was not called, and run over the
    /// same 180 it refutes **none** of them. That zero is why replacing the
    /// unconditional `isInferredPure: true` moved 0 advisory rows, and why the
    /// defect was reported as a latent unsoundness rather than a live wrong
    /// answer — calling the advisory *unsound* on the strength of the code path
    /// alone would have been manufacturing a defect that was not there.
    ///
    /// It is deliberately re-derived from the **accessor syntax**, not read off
    /// `summary.isInferredPure`. Since the fix those two agree by construction,
    /// so reading the summary would be asking the fix to confirm itself. The day
    /// this stops being zero, a real getter in this repo has become impure and
    /// the advisory correctly drops it — which is a fact worth seeing, not a
    /// failure.
    @Test("no computed property in this repo is refuted by the accessor oracle")
    func noAccessorInThisRepoIsRefuted() throws {
        let summaries = try FunctionScanner.scan(directory: Self.packageSourcesRoot)
        // Keyed by (file, name), not by name alone — a bare-name key silently
        // collapses same-named properties in different files, which would shrink
        // the denominator without saying so.
        let computedKeys = Set(summaries.filter(\.isComputedProperty).map {
            "\(URL(fileURLWithPath: $0.location.file).lastPathComponent)#\($0.name)"
        })
        let inferrer = PurityInferrer()
        var matched: Set<String> = []
        var refutedByOracle: [String] = []
        for file in SwiftSourceFiles.sorted(in: Self.packageSourcesRoot) {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let collector = CensusFunctionCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: source))
            for (name, accessor) in collector.accessorsByName {
                let key = "\(file.lastPathComponent)#\(name)"
                guard computedKeys.contains(key) else { continue }
                matched.insert(key)
                if !inferrer.isPure(accessor), !Self.knownFalseRefutations.contains(key) {
                    refutedByOracle.append(key)
                }
            }
        }
        // **Three FALSE refutations, recorded rather than dodged.**
        //
        // `RolePostcondition` declares `case shuffled`, and SEI's marker set treats the
        // token `shuffled` as a nondeterminism source — meaning `Array.shuffled()`. Every
        // getter that mentions `.shuffled` in a `switch` therefore reads as impure:
        //
        //     case .shuffled: "the result is a permutation of the input"
        //     self != .reversed && self != .shuffled
        //
        // **An enum case named `shuffled` is not a call to `shuffled()`.** This is the
        // token-collision class `purity-refuting-fixpoint-census.md` already measured at
        // **61% false** (46 of 75 cascade rows were `classify`-style name collisions),
        // arriving inside the oracle rather than in a census built on top of it.
        //
        // **Why an allowlist and not a rename.** Renaming the case to dodge the marker
        // would make this guard pass and leave the oracle's false positive unrecorded —
        // and the `rawValue` must stay `"shuffled"` regardless, because it matches the
        // Swift function name the role is named for. Naming the entries keeps the guard
        // catching NEW refutations, which is what it is for.
        #expect(
            matched == computedKeys,
            "matched \(matched.count) accessors for \(computedKeys.count) computed-property summaries"
        )
        #expect(
            refutedByOracle.isEmpty,
            """
            A getter in this repo is now refuted by the accessor oracle: \
            \(refutedByOracle.prefix(10).joined(separator: ", ")). Not a defect — the \
            advisory correctly drops it. Re-take the A/B in the census doc, which records \
            this as zero.
            """
        )
    }
}
