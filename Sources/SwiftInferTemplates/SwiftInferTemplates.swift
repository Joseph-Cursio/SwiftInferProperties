import Foundation
import SwiftInferCore

/// SwiftInferTemplates — TemplateEngine template registry.
///
/// PRD v0.3 §5.2 specifies eight shipped templates: round-trip, idempotence,
/// commutativity, associativity, monotonicity, identity-element,
/// invariant-preservation, inverse-pair. M1.3 shipped **idempotence**; M1.4
/// adds **round-trip** + cross-function pairing; subsequent milestones add
/// the remaining six.
public enum SwiftInferTemplates {}

/// Static registry that orchestrates every M1 template against a corpus of
/// `FunctionSummary` records. Kept in `SwiftInferTemplates` (rather than the
/// CLI) so the discovery pipeline is reachable from tests without going
/// through ArgumentParser, and so v1.1's constraint-engine upgrade has a
/// single seam to slot into.
public enum TemplateRegistry {

    /// Run every M1 template against `summaries`. Output is sorted by
    /// (file path, line) of the first evidence row so the byte-identical-
    /// reproducibility guarantee (PRD §16 #6) holds across runs.
    ///
    /// Currently runs idempotence (per summary) and round-trip (per pair
    /// produced by `FunctionPairing.candidates(in:)`). Both templates are
    /// allowed to fire on the same function — overlap (e.g. `parse`/
    /// `format` matching both round-trip's curated inverse list and
    /// idempotence's `format` verb) is left for the M3 contradiction-
    /// detection pass to deduplicate.
    public static func discover(in summaries: [FunctionSummary]) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        for summary in summaries {
            if let suggestion = IdempotenceTemplate.suggest(for: summary) {
                suggestions.append(suggestion)
            }
        }
        for pair in FunctionPairing.candidates(in: summaries) {
            if let suggestion = RoundTripTemplate.suggest(for: pair) {
                suggestions.append(suggestion)
            }
        }
        return suggestions.sorted(by: lessThan)
    }

    /// Convenience: scan `directory` recursively, run every M1 template
    /// against the resulting summaries, and filter out any suggestion
    /// whose identity matches a `// swiftinfer: skip <hash>` marker
    /// found anywhere in the scanned `.swift` files (PRD §7.5).
    public static func discover(in directory: URL) throws -> [Suggestion] {
        let summaries = try FunctionScanner.scan(directory: directory)
        let skipHashes = try SkipMarkerScanner.skipHashes(in: directory)
        return discover(in: summaries).filter { suggestion in
            !skipHashes.contains(suggestion.identity.normalized)
        }
    }

    private static func lessThan(_ lhs: Suggestion, _ rhs: Suggestion) -> Bool {
        let lhsLoc = lhs.evidence.first?.location
        let rhsLoc = rhs.evidence.first?.location
        guard let lhsLoc, let rhsLoc else {
            return lhs.templateName < rhs.templateName
        }
        if lhsLoc.file != rhsLoc.file {
            return lhsLoc.file < rhsLoc.file
        }
        if lhsLoc.line != rhsLoc.line {
            return lhsLoc.line < rhsLoc.line
        }
        return lhs.templateName < rhs.templateName
    }
}
