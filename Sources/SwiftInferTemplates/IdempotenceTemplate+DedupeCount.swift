import SwiftInferCore

/// #671's count laws, carried beside idempotence on a recognised dedupe whose body passes the gate
/// (`DedupeBodyReader`, SwiftInferProperties#711).
///
/// **The row stays idempotence's, at idempotence's tier, on purpose.** C1 and C2 are owed by any
/// dedupe the gate admits, while idempotence is a conjecture, so the count laws could argue for a
/// higher tier. They do not get one here: the census found **one** emittable row
/// (`docs/measurements/dedupe-count-law-census.md`), and one row cannot calibrate a tier. The match
/// changes what the accepted stub checks and what the row explains, and nothing about its score.
extension IdempotenceTemplate {

    /// The "why suggested" line naming the body route, or nothing when the gate did not admit.
    static func dedupeCountWhySuggested(for summary: FunctionSummary) -> [String] {
        guard let body = summary.bodySignals.dedupeBody else { return [] }
        let route = switch body.route {
        case .set:
            "a `Set` local, and an element reaches the result only through a successful insert"

        case .dictionary:
            "a dictionary local written once per key, every skip guarded by a read of that key, "
                + "and a return of its values"
        }
        let equality = body.keepsFirst
            ? "Keep-first, so C2 is stated as equality: `f(value + value) == f(value)`."
            : "Its result is in hash order, so C2 compares counts only."
        return [
            "The body keeps one element per key: \(route). So the accepted stub also checks two count "
                + "laws idempotence cannot see (#671): C1, a singleton survives "
                + "(`value.allSatisfy { f([$0]).count == 1 }`), which fails a dedupe that drops "
                + "everything; and C2, a duplicate of everything adds nothing "
                + "(`f(value + value).count == f(value).count`), which fails one that no longer "
                + "deduplicates. \(equality)",
        ]
    }

    /// The match the row carries: the body gate's route, or `nil` when the gate did not admit.
    static func dedupeCountMatch(for summary: FunctionSummary) -> TemplateMatch? {
        summary.bodySignals.dedupeBody.map(TemplateMatch.dedupeCount)
    }

    /// What the count laws cannot see.
    static let dedupeCountCaveat =
        "C1 and C2 cannot see a wrong key: every element of `value + value` collides with its twin "
        + "under any key, so a dedupe keyed on the wrong field passes both. Neither law checks which "
        + "elements count as duplicates."
}
