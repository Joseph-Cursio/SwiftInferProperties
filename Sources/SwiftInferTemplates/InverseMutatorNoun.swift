import SwiftInferCore

/// What an inverse-mutator pair's two moves are moving — the **noun**, read off the name after
/// the direction verb, and off the first argument label when the name carries none.
///
/// ## Why this exists
///
/// `InverseMutatorPairing` matched the VERB and nothing else: `name.lowercased().hasPrefix(stem)`,
/// with `members.first(where:)` on each side. That pairs the first `add…` on a type with the first
/// `remove…` whatever follows either one, and
/// `docs/measurements/normal-form-state-machine-writers.md` measured what it costs — **5 of the 16
/// `state-machine` rows across both corpus lists name a pair the code does not owe**:
///
/// - `addRule(_:to:)` × `removeOption(key:)` — different nouns, and `removeRule(_:from:)` is 14
///   lines below the `addRule` that got paired.
/// - `addDisabledRuleIfNeeded(to:)` × `removeOptInRuleIfPresent(from:)` — different rules, and the
///   right partner is in the same file.
/// - `addOrUpdate(for:user:password:persist:)` × `remove(for:)` — an **upsert** is not an add: it
///   overwrites, so removing restores no prior value.
/// - `add(_ anObject: AnyObject)` × `removeObject(at index: Int)` — adds a **value**, removes an
///   **index**, so the composition is the identity only at the last one.
///
/// **This is `hasPrefix` on a verb failing to bound a compound name — the mechanism
/// `docs/measurements/subset-name-contract-gate.md` settled for `filter-subset` (#476), at a
/// second site.** A verb leads in English method names and the tail can revoke what it promised.
///
/// ## What the shape of the rule is forced by
///
/// Every clause below is here because a measured row needs it, and they are listed in
/// `InverseMutatorNounTests` one test per row. Two are worth naming here because they are not
/// obvious:
///
/// **The noun is sometimes in the LABEL, not the name.** GRDB spells both moves
/// `add(transactionObserver:extent:)` / `remove(transactionObserver:)` — bare `add`/`remove`, with
/// the whole noun in the label — and swift-foundation's `push(value:)` / `popValue()` puts it in
/// the label on one side and the name on the other. **The corpus-funnel repositories contain no
/// example of either**: every noun there is in the name, so a gate written against that corpus
/// alone would have read `""` for both GRDB sides and admitted `add(function:)` ×
/// `remove(collation:)` for the wrong reason.
///
/// **An empty BACKWARD noun is excused, an empty forward one is not.** `navigateUp()` names
/// nothing because there is only one way up — the shape `InverseMutatorPairing`'s own
/// `isMove` already exempts the backward side for — while `add(_ anObject:)` names nothing
/// because it is the side that is supposed to say *what*. The excuse is also limited to a type
/// with exactly one forward move, since with two there is no saying which one the single backward
/// undoes.
enum InverseMutatorNoun {

    /// Leading prepositions the direction conventions already imply, so `addTo…` and
    /// `removeFrom…` name the same noun. Required by
    /// `addToRecentWorkspaces` × `removeFromRecentWorkspaces`, which is a true pair.
    private static let directionPrepositions: Set<String> = ["to", "from", "into", "onto"]

    /// Trailing conditional qualifiers, which say *whether* the move ran and never *what* it
    /// moved. Required by `addDisabledRuleIfNeeded` × `removeDisabledRuleIfPresent` — and it is
    /// the same normalisation that keeps `removeOptInRuleIfPresent` correctly OUT.
    private static let conditionalQualifiers: Set<String> = [
        "needed", "present", "absent", "missing", "possible"
    ]

    /// Tokens that announce the name covers a SECOND operation, so the move is not one move.
    ///
    /// `addOrUpdate` is the measured exhibit and it is a disjunction: the update branch overwrites
    /// a value the remove cannot put back, so `remove ∘ addOrUpdate == id` is false exactly when
    /// the entry already existed. **Deliberately kept to connectives**, and deliberately NOT
    /// routed through `FilterSubsetTemplate.nameAnnouncesASecondOperation` — that list is tuned
    /// for a different template's population and #476 records that a wrong entry there withdraws a
    /// real law. One rule, one owner.
    private static let connectives: Set<String> = ["or", "and", "then", "plus"]

    /// The tokens naming what this move moves, or `[]` when it names nothing.
    ///
    /// `stem` is the rule's own direction verb (`add`, `navigateto`, `push`), which may span more
    /// than one token — `navigateToFolder` tokenises to `[navigate, to, folder]` and the stem
    /// `navigateto` consumes the first two.
    static func tokens(of summary: FunctionSummary, afterStem stem: String) -> [String] {
        var remainder = dropStem(from: StreamConsumption.camelCaseTokens(summary.name), stem: stem)
        remainder = normalized(remainder)
        if remainder.isEmpty, let label = summary.parameters.first?.label {
            remainder = normalized(StreamConsumption.camelCaseTokens(label))
        }
        return remainder
    }

    /// Whether the name covers a second operation, so no single backward move undoes it.
    static func announcesASecondOperation(_ summary: FunctionSummary, afterStem stem: String) -> Bool {
        let remainder = dropStem(from: StreamConsumption.camelCaseTokens(summary.name), stem: stem)
        return remainder.contains { connectives.contains($0) }
    }

    /// Drop the leading tokens that spell `stem`, matching whole tokens rather than characters —
    /// the rule `docs/measurements/monotonicity-subject-census.md` settled on after an exact
    /// whole-name match missed `_cos` and a substring match read `distance(to:)` as trig.
    private static func dropStem(from tokens: [String], stem: String) -> [String] {
        var consumed = ""
        for (index, token) in tokens.enumerated() {
            consumed += token
            if consumed == stem { return Array(tokens.dropFirst(index + 1)) }
            if !stem.hasPrefix(consumed) { break }
        }
        return tokens
    }

    /// Strip the leading direction preposition and the trailing conditional qualifier.
    private static func normalized(_ tokens: [String]) -> [String] {
        var result = tokens
        if let first = result.first, directionPrepositions.contains(first) {
            result = Array(result.dropFirst())
        }
        if result.count >= 2,
           result[result.count - 2] == "if",
           conditionalQualifiers.contains(result[result.count - 1]) {
            result = Array(result.dropLast(2))
        }
        return result
    }
}
