import Foundation
import SwiftInferCore

/// V1.150 — the user-facing pointer at what to do about Unverifiable picks, surfaced wherever
/// they appear (`prove-then-show`, `report`).
///
/// **Rewritten 2026-08-13.** It used to be one sentence naming one cause:
///
/// > *an Unverifiable pick means the strategist has no generator for its carrier. Add
/// > `static func gen() -> Gen<T>` for that type …*
///
/// Measured on `SwiftFormatRuleStudioCore`, that cause accounted for **1 of 18** Unverifiable
/// rows (`docs/measurements/exploratory-swiftformatrulestudio.md` §5.1). The other 17 were 9
/// missing composers, 6 `private` subjects and 2 instance-method shapes, and a `gen()` moves
/// none of them. The hint now counts the causes and prescribes against what is actually there.
///
/// The `gen()` hook is still named — it is a real escape hatch and was genuinely
/// undiscoverable — but only for the rows it unblocks.
enum GenHookHint {

    /// Lines for a set of Unverifiable records: one breakdown, then a remedy per cause
    /// present, largest first.
    ///
    /// **Every cause present gets a line, rather than only the dominant one.** The failure
    /// being corrected is a *single* prescription standing in for a mixed population, and
    /// picking the biggest bucket is the same mistake with better arithmetic — on the measured
    /// subject it would have prescribed against 9 of 18 and still implied it covered the rest.
    /// Each line carries its own count, so a reader can see what a fix is worth before doing
    /// it.
    ///
    /// Returns `[]` for an empty input: a caller with nothing Unverifiable prints nothing,
    /// rather than a heading over no rows.
    static func lines(details: [String?], indent: String = "") -> [String] {
        guard !details.isEmpty else { return [] }
        let causes = details.map { UnverifiableCause.classify(detail: $0) }
        let counts = Dictionary(grouping: causes) { $0 }.mapValues(\.count)
        // Sorted by count then by the enum's own order, so equal counts do not reorder between
        // runs — a report that shuffles its own lines reads as movement where there is none.
        let ranked = UnverifiableCause.allCases
            .compactMap { cause in counts[cause].map { (cause, $0) } }
            .sorted { ($0.1, rank($0.0)) > ($1.1, rank($1.0)) }

        let breakdown = ranked.map { "\($0.0.label) \($0.1)" }.joined(separator: ", ")
        return [indent + "Unverifiable by cause: " + breakdown]
            + ranked.map { cause, count in
                "\(indent)  · \(count) — \(cause.remedy)"
            }
    }

    private static func rank(_ cause: UnverifiableCause) -> Int {
        UnverifiableCause.allCases.firstIndex(of: cause).map { -$0 } ?? 0
    }
}
