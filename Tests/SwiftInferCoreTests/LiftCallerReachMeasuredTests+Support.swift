import Foundation

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// The caller index for `LiftCallerReachMeasuredTests`. Split out only for the 400-line
/// file cap; the reasoning that governs both lives in that suite's header.
extension LiftCallerReachMeasuredTests {

    struct Reading {
        let restricted: Int
        let callersIndexed: Int
        let withAnyCaller: Int
        let withVisibleCaller: Int
        let withSingleVisibleCaller: Int
        let samples: [String]
        /// Suggestions whose subject is `notVisibleToTests` — the rows that actually
        /// decline for visibility, and the population the caveat would attach to.
        let suggestionsOnRestricted: Int
        /// …of those, how many could be told which visible caller to lift to.
        let suggestionsWithVisibleCaller: Int

        var withoutCaller: Int { restricted - withAnyCaller }
    }

    static let reading: Reading? = measure()

    private static func measure() -> Reading? {
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        guard let scanned = try? FunctionScanner.scanCorpus(directory: root) else { return nil }

        // `notVisibleToTests` only — `internalOrSPI` is reached by `@testable` and
        // `nestedLocal` is a different problem, both per `AccessRestriction`'s own doc.
        let subjects = scanned.restricted
            .filter { $0.restriction == .notVisibleToTests }
            .map(\.summary)
        let restrictedLocations = Set(subjects.map(\.location))

        // Callers, bucketed BY FILE. Same-file is sound rather than heuristic: `private`
        // and `fileprivate` are file-scoped, so a caller of one of these subjects must be
        // in the same file. That is what makes a reverse *name* index safe here — a
        // `normalize` in another type cannot be a caller of this `normalize`.
        var byFile: [String: [FunctionSummary]] = [:]
        for summary in scanned.summaries where !summary.calledFreeFunctionNames.isEmpty {
            byFile[summary.location.file, default: []].append(summary)
        }
        let callersIndexed = byFile.values.reduce(0) { $0 + $1.count }

        var withAny = 0, withVisible = 0, withSingleVisible = 0
        var samples: [String] = []
        for subject in subjects {
            let candidates = (byFile[subject.location.file] ?? []).filter { caller in
                caller.location != subject.location
                    && caller.calledFreeFunctionNames.contains(subject.name)
            }
            guard !candidates.isEmpty else { continue }
            withAny += 1

            let visible = candidates.filter { !restrictedLocations.contains($0.location) }
            guard !visible.isEmpty else { continue }
            withVisible += 1
            if visible.count == 1 { withSingleVisible += 1 }

            if samples.count < 40 {
                let file = URL(fileURLWithPath: subject.location.file).lastPathComponent
                let named = visible.map(\.name).sorted().joined(separator: ", ")
                samples.append("\(subject.name) @ \(file) -> \(named)")
            }
        }

        let arm = suggestionArm(
            scanned: scanned, subjects: subjects,
            byFile: byFile, restrictedLocations: restrictedLocations
        )

        return Reading(
            restricted: subjects.count,
            callersIndexed: callersIndexed,
            withAnyCaller: withAny,
            withVisibleCaller: withVisible,
            withSingleVisibleCaller: withSingleVisible,
            samples: samples.sorted(),
            suggestionsOnRestricted: arm.onRestricted,
            suggestionsWithVisibleCaller: arm.withCaller
        )
    }

    /// The population the caveat attaches to: suggestions whose subject is one of these
    /// restricted functions. `scanCorpus`'s `restricted` list is the same signal
    /// `UnverifiableCause.subjectNotVisible` fires on, so this is the decline bucket
    /// without needing a verify run to produce it.
    private static func suggestionArm(
        scanned: ScannedCorpus,
        subjects: [FunctionSummary],
        byFile: [String: [FunctionSummary]],
        restrictedLocations: Set<SourceLocation>
    ) -> (onRestricted: Int, withCaller: Int) {
        let liftable = subjects.filter { subject in
            (byFile[subject.location.file] ?? []).contains { caller in
                caller.location != subject.location
                    && caller.calledFreeFunctionNames.contains(subject.name)
                    && !restrictedLocations.contains(caller.location)
            }
        }
        let liftableSubjects = Set(liftable.map(\.location))
        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        var onRestricted = 0, withCaller = 0
        for suggestion in suggestions {
            let locations = suggestion.evidence.map(\.location)
            guard locations.contains(where: restrictedLocations.contains) else { continue }
            onRestricted += 1
            if locations.contains(where: liftableSubjects.contains) { withCaller += 1 }
        }
        return (onRestricted, withCaller)
    }
}
