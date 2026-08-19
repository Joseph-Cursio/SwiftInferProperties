import Foundation

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// The cross-type split for `CrossTypePairCensusMeasuredTests`. Split out only for the
/// 400-line file cap; the reasoning lives in that suite's header.
extension CrossTypePairCensusMeasuredTests {

    struct Reading {
        let corpus: String
        let roundTrip: Int
        let crossType: Int
        let sameType: Int
        /// Cross-type pairs where **both** carriers look like code generators. Named
        /// because that is the shape which made the parameter-role class self-only, and
        /// this census exists to find out whether the same is true here.
        let emitterPairs: Int
        let samples: [String]
    }

    /// A carrier whose name marks it as a code generator. Deliberately a **name** test and
    /// deliberately narrow: it is used only to characterise a population, never to gate
    /// anything, so a miss costs a line of description rather than a suggestion.
    static func looksLikeGenerator(_ name: String) -> Bool {
        ["Emitter", "Builder", "Renderer", "Generator", "Composer"].contains { name.contains($0) }
    }

    static let readings: [Reading] = PartialPurityConsumerMeasuredTests.corpora.compactMap { corpus in
        guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.root) else {
            return nil
        }
        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        let summaryAt = Dictionary(scanned.summaries.map { ($0.location, $0) }) { first, _ in first }

        var roundTrip = 0, crossType = 0, emitterPairs = 0
        var samples: [String] = []
        for suggestion in suggestions where suggestion.templateName == "round-trip" {
            roundTrip += 1
            let types = suggestion.evidence
                .compactMap { summaryAt[$0.location]?.containingTypeName }
            guard Set(types).count > 1, let forward = types.first, let reverse = types.last
            else { continue }
            crossType += 1
            if looksLikeGenerator(forward), looksLikeGenerator(reverse) { emitterPairs += 1 }
            if samples.count < 20 { samples.append("\(forward) -> \(reverse)") }
        }
        return Reading(
            corpus: corpus.name,
            roundTrip: roundTrip,
            crossType: crossType,
            sameType: roundTrip - crossType,
            emitterPairs: emitterPairs,
            samples: samples.sorted()
        )
    }
}
