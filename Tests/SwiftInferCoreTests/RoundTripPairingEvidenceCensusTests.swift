import Foundation
import SwiftInferTemplates
import Testing

@testable import SwiftInferCore

/// **What licenses a `round-trip` pairing?** — `docs/plans/round-trip-pairing-evidence-scope.md`.
///
/// Open-threads row 70: `round-trip` can choose an inverse on type signature alone —
/// `Rotation.yaw(r.angle) == r`, and unrelated `Vector -> Vector` functions paired because their
/// types line up. Two gates were measured and closed (degrees of freedom: not computable;
/// the `Possible` tier: its refutation rate reverses between subjects). This census asks the
/// question neither gate did: for every `round-trip` suggestion, which of the template's OWN
/// signals backed the pairing — and, after a hand-check, whether the signal-less class is
/// separable from real round trips.
///
/// It only dumps: every `round-trip` suggestion over the manifest corpora plus any extra roots,
/// with its tier, signals and both functions, as JSON for the classification script.
///
///     SWIFT_INFER_PAIRING_CENSUS=/out/rows.json \
///     SWIFT_INFER_PAIRING_EXTRA=/path/Euclid/Sources:/path/swift-docc/Sources \
///     swift test --filter RoundTripPairingEvidenceCensus
@Suite(
    "Census — what licenses a round-trip pairing",
    .serialized,
    .enabled(
        if: ProcessInfo.processInfo.environment["SWIFT_INFER_PAIRING_CENSUS"] != nil,
        "opt-in census; set SWIFT_INFER_PAIRING_CENSUS=<output json>"
    )
)
struct RoundTripPairingEvidenceCensusTests {

    struct Row: Encodable {
        let corpus: String
        let tier: String
        let score: Int
        let signals: [SignalRow]
        let forward: FunctionRow
        let inverse: FunctionRow?
        let carrier: String?
    }

    struct SignalRow: Encodable {
        let kind: String
        let weight: Int
        let detail: String
    }

    struct FunctionRow: Encodable {
        let displayName: String
        let signature: String
        let file: String
        let line: Int
        let qualifiedTypeName: String?
        let parameterInternalNames: [String]
    }

    static func function(_ evidence: Evidence) -> FunctionRow {
        FunctionRow(
            displayName: evidence.displayName,
            signature: evidence.signature,
            file: evidence.location.file,
            line: evidence.location.line,
            qualifiedTypeName: evidence.qualifiedTypeName,
            parameterInternalNames: evidence.parameterInternalNames
        )
    }

    static func rows(corpus: String, root: URL) -> [Row] {
        guard let scanned = try? FunctionScanner.scanCorpus(directory: root) else { return [] }
        let discovered = TemplateRegistry.discover(
            in: scanned.summaries,
            identities: scanned.identities,
            typeDecls: scanned.typeDecls
        )
        return discovered.filter { $0.templateName == "round-trip" }.compactMap { suggestion in
            guard let first = suggestion.evidence.first else { return nil }
            return Row(
                corpus: corpus,
                tier: suggestion.score.tierLabel,
                score: suggestion.score.total,
                signals: suggestion.score.signals.map {
                    SignalRow(kind: "\($0.kind)", weight: $0.weight, detail: $0.detail)
                },
                forward: function(first),
                inverse: suggestion.evidence.dropFirst().first.map(function),
                carrier: suggestion.carrier
            )
        }
    }

    @Test("dump every round-trip suggestion with its pairing evidence")
    func dump() throws {
        let environment = ProcessInfo.processInfo.environment
        let output = URL(fileURLWithPath: environment["SWIFT_INFER_PAIRING_CENSUS"]!)
        var all: [Row] = []
        for corpus in CorpusManifest.available {
            all += Self.rows(corpus: corpus.id, root: corpus.primaryRoot)
        }
        for path in (environment["SWIFT_INFER_PAIRING_EXTRA"] ?? "").split(separator: ":") {
            let root = URL(fileURLWithPath: String(path))
            all += Self.rows(corpus: "extra:" + root.deletingLastPathComponent().lastPathComponent, root: root)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(all).write(to: output)
        print("pairing census: \(all.count) round-trip rows over \(CorpusManifest.available.count) manifest corpora")
        #expect(!all.isEmpty)
    }
}
