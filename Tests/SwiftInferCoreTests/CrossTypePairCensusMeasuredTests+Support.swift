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

    /// **Every corpus the manifest resolves, not item 34's trio.** The first run of this
    /// census used three, found OrderedCollections yielding **1** round-trip suggestion,
    /// and concluded the control was uninformative. That was true of those three — and the
    /// parameter-role census, re-taken across the manifest the same day, had both of its
    /// reasons refuted. A conclusion drawn from the same thin universe is not evidence.
    static let readings: [Reading] = CorpusManifest.available.compactMap { corpus in
        guard let scanned = try? FunctionScanner.scanCorpus(directory: corpus.primaryRoot) else {
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
            corpus: "\(corpus.id) (\(corpus.swiftFileCount) files)",
            roundTrip: roundTrip,
            crossType: crossType,
            sameType: roundTrip - crossType,
            emitterPairs: emitterPairs,
            samples: samples.sorted()
        )
    }
}
