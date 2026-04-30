import Foundation
import SwiftInferCore

/// SwiftInferTemplates — TemplateEngine template registry.
///
/// PRD v0.3 §5.2 specifies eight shipped templates: round-trip, idempotence,
/// commutativity, associativity, monotonicity, identity-element,
/// invariant-preservation, inverse-pair. M1.3 shipped **idempotence**; M1.4
/// adds **round-trip** + cross-function pairing; M2.3 adds **commutativity**;
/// M2.4 adds **associativity** with reducer/builder usage as a new
/// type-flow signal; subsequent milestones add the remaining four.
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
    /// `vocabulary` is the project-extensible naming layer per PRD §4.5;
    /// templates consult it alongside their curated lists. Defaults to
    /// `.empty` so M1 call sites that haven't been updated for the M2
    /// vocabulary plumbing keep compiling.
    ///
    /// Currently runs idempotence + commutativity + associativity (per
    /// summary) and round-trip (per pair produced by
    /// `FunctionPairing.candidates(in:)`). Multiple templates are
    /// allowed to fire on the same function — overlap (e.g. `merge`
    /// matching both commutativity and associativity since they share
    /// the same curated naming list per v0.2 §5.2; or `add` matching
    /// idempotence + commutativity + associativity if the type pattern
    /// allows) is left for the M3 contradiction-detection pass and the
    /// M7 algebraic-structure-composition (§5.4) cluster to deduplicate.
    public static func discover(
        in summaries: [FunctionSummary],
        vocabulary: Vocabulary = .empty
    ) -> [Suggestion] {
        // Corpus-wide union of names referenced as the closure-position
        // argument of any `.reduce(_, X)` call — feeds the associativity
        // reducer/builder-usage signal (PRD §5.3, +20). Computed once per
        // discover so per-summary template calls are O(1) lookups.
        let reducerOps: Set<String> = Set(summaries.flatMap(\.bodySignals.reducerOpsReferenced))
        var suggestions: [Suggestion] = []
        for summary in summaries {
            if let suggestion = IdempotenceTemplate.suggest(for: summary, vocabulary: vocabulary) {
                suggestions.append(suggestion)
            }
            if let suggestion = CommutativityTemplate.suggest(for: summary, vocabulary: vocabulary) {
                suggestions.append(suggestion)
            }
            if let suggestion = AssociativityTemplate.suggest(
                for: summary,
                vocabulary: vocabulary,
                reducerOps: reducerOps
            ) {
                suggestions.append(suggestion)
            }
        }
        for pair in FunctionPairing.candidates(in: summaries) {
            if let suggestion = RoundTripTemplate.suggest(for: pair, vocabulary: vocabulary) {
                suggestions.append(suggestion)
            }
        }
        return suggestions.sorted(by: lessThan)
    }

    /// Convenience: scan `directory` recursively, run every M1 template
    /// against the resulting summaries, and filter out any suggestion
    /// whose identity matches a `// swiftinfer: skip <hash>` marker
    /// found anywhere in the scanned `.swift` files (PRD §7.5).
    public static func discover(
        in directory: URL,
        vocabulary: Vocabulary = .empty
    ) throws -> [Suggestion] {
        let summaries = try FunctionScanner.scan(directory: directory)
        let skipHashes = try SkipMarkerScanner.skipHashes(in: directory)
        return discover(in: summaries, vocabulary: vocabulary).filter { suggestion in
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
