import Foundation
import SwiftInferCore

/// SwiftInferTemplates — TemplateEngine template registry.
///
/// PRD v0.3 §5.2 specifies eight shipped templates: round-trip, idempotence,
/// commutativity, associativity, monotonicity, identity-element,
/// invariant-preservation, inverse-pair. M1.3 ships **idempotence**; M1.4
/// adds round-trip + cross-function pairing; subsequent milestones add the
/// remaining six.
public enum SwiftInferTemplates {}

/// Static registry that orchestrates every M1 template against a corpus of
/// `FunctionSummary` records. Kept in `SwiftInferTemplates` (rather than the
/// CLI) so the discovery pipeline is reachable from tests without going
/// through ArgumentParser, and so v1.1's constraint-engine upgrade has a
/// single seam to slot into.
public enum TemplateRegistry {

    /// Run every M1 template against `summaries`. Output is sorted by
    /// (file path, line) so the byte-identical-reproducibility guarantee
    /// (PRD §16 #6) holds across runs.
    public static func discover(in summaries: [FunctionSummary]) -> [Suggestion] {
        var suggestions: [Suggestion] = []
        for summary in summaries {
            if let suggestion = IdempotenceTemplate.suggest(for: summary) {
                suggestions.append(suggestion)
            }
        }
        return suggestions.sorted(by: lessThan)
    }

    /// Convenience: scan `directory` recursively and run every M1 template
    /// against the resulting summaries.
    public static func discover(in directory: URL) throws -> [Suggestion] {
        let summaries = try FunctionScanner.scan(directory: directory)
        return discover(in: summaries)
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
