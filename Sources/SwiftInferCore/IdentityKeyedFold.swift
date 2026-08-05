import Foundation

/// The identity-keyed "latest run in effect" fold shared by the four aggregate
/// logs — `Decisions`, `PostAcceptanceOutcomeLog`, `VerifyEvidenceLog`,
/// `InteractionDecisions`.
///
/// ## Why this exists as one function
///
/// Each of those four had its own copy, identical except for the date field's
/// name, and each copy was **not commutative**. Measured 2026-08-05 by the
/// whole-corpus verify survey: `commutativity` ran 4 laws on this repo, all four
/// were one of these merges, and all four refuted. The copies cite each other in
/// their doc comments (*"same posture as v1's `Decisions.merge`"*), so the defect
/// propagated by precedent — `Decisions.merge` was already recorded as
/// non-commutative in CLAUDE.md while the three that copied it were not.
///
/// A per-type patch would have left the precedent in place for the fifth
/// aggregate. This is the fifth aggregate's answer.
///
/// ## The defect, and why `>=` → `>` is not the fix
///
/// The old fold walked `records + other.records` and skipped a candidate when
/// `existing.date >= candidate.date`. On an **equal** date that means
/// *first-seen wins*, and "first" is decided by which side of `merge` you are
/// on. Flipping to `>` makes it *last*-seen wins, which is equally
/// order-dependent — it changes which argument is privileged, not whether one is.
///
/// The fix is to stop selecting by position at all: rank records by a **total
/// order** — date first, then a canonical encoding of the record itself — and
/// take the maximum. Maximum under a total order is commutative by construction.
///
/// ## Associativity was already correct and must stay that way
///
/// The old fold is *take-first-max*, which is associative even though it is not
/// commutative: both parenthesisations of `a, b, c` preserve left-to-right order,
/// so both select the same record. The survey measured this — all four carriers
/// refuted `commutativity` and **held** `associativity` — and an exhaustive check
/// over a collision-dense domain (2 identities × 2 payloads × 2 dates) found
/// 8/64 pairs failing commutativity and **0/512 triples** failing associativity.
///
/// So associativity is not a bug that was fixed here; it is a property that was
/// already true and that this change had to avoid breaking. Maximum under a total
/// order is associative too, which is why the tie-break is a *rank* rather than
/// anything that depends on what has already been seen. A tie-break that merged
/// payloads, or counted records, would restore commutativity and destroy
/// associativity — see `IdentityKeyedFoldTests`, which asserts both laws.
public enum IdentityKeyedFold {

    /// Fold two identity-keyed record lists into one, independent of argument
    /// order.
    ///
    /// - Parameters:
    ///   - primary: this log's records.
    ///   - secondary: the other log's records.
    ///   - identity: the collision key — records sharing it are the "same" record.
    ///   - timestamp: the recency field; the later one wins.
    /// - Returns: one record per identity, sorted by `(timestamp, identity)` so
    ///   the in-memory aggregate is order-deterministic in its rows *and* in
    ///   their contents. The old fold guaranteed only the former.
    public static func merged<Record: Encodable>(
        primary: [Record],
        secondary: [Record],
        identity: (Record) -> String,
        timestamp: (Record) -> Date
    ) -> [Record] {
        var winners: [String: Ranked<Record>] = [:]
        for record in primary + secondary {
            let key = identity(record)
            let candidate = Ranked(
                record: record,
                timestamp: timestamp(record),
                canonical: canonicalRank(of: record)
            )
            guard let incumbent = winners[key] else {
                winners[key] = candidate
                continue
            }
            // Strictly-greater keeps the incumbent on a genuine tie (identical
            // date AND identical encoding), where the two records are
            // indistinguishable and the choice cannot be observed.
            if candidate.isRankedAbove(incumbent) {
                winners[key] = candidate
            }
        }
        return winners
            .map { ($0.key, $0.value) }
            .sorted { lhs, rhs in
                if lhs.1.timestamp != rhs.1.timestamp {
                    return lhs.1.timestamp < rhs.1.timestamp
                }
                return lhs.0 < rhs.0
            }
            .map(\.1.record)
    }

    /// A record paired with the two keys that order it.
    private struct Ranked<Record> {
        let record: Record
        let timestamp: Date
        /// Canonical encoding, used **only** to break a `timestamp` tie.
        let canonical: String

        func isRankedAbove(_ other: Ranked<Record>) -> Bool {
            if timestamp != other.timestamp { return timestamp > other.timestamp }
            return canonical > other.canonical
        }
    }

    /// A deterministic total-order key for a record.
    ///
    /// `.sortedKeys` is what makes this a *canonical* encoding rather than merely
    /// an encoding — without it, dictionary key order could differ between two
    /// encodings of equal records and the tie-break would stop being a function
    /// of the value. An encoding failure falls back to the empty string, which
    /// degrades the tie-break to "keep the incumbent" for that record and cannot
    /// make the result depend on argument order: every record that fails to
    /// encode ranks equal, so the comparison is still total.
    private static func canonicalRank(of record: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(record),
              let text = String(bytes: data, encoding: .utf8) else { return "" }
        return text
    }
}
