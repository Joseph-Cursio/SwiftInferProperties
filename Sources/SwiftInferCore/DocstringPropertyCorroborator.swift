/// Corroborates a shape-matched algebraic law with the function's own docstring.
///
/// **Corroborate-only, never infer.** This is the load-bearing distinction from
/// the `DocstringAdvisor` channel (`--docstring-advice`). The advisor surfaces a
/// documented reference definition as a *separate* advisory. This corroborator
/// instead feeds the **default-path template inference**: a template that has
/// already matched a candidate by *shape* (and possibly *name*) consults the
/// docstring, and if the prose independently asserts the same property, the
/// template earns a positive `Signal.docstringCorroboration` (+15). It can only
/// *strengthen* a candidate the shape already produced — a docstring alone can
/// never surface a law the shape didn't match. Refutability is preserved: the
/// `(T) -> T` (or `self -> Self`) shape still gates; the prose only raises the
/// tier of an already-legitimate candidate (typically Possible 30 → Likely 45,
/// so a documented-but-not-curated-name idempotent function surfaces by default).
///
/// **Precision discipline (mirrors `DocstringAdvisor.isContract`).** Each
/// property carries a tight, *discriminating* assertion vocabulary — the bare
/// word (`idempotent`), or a phrase unique to that property (`self-inverse`).
/// Ambiguous prose shared across properties (a bare "applying twice", which fits
/// both idempotence and involution) corroborates **neither**. Every positive
/// match is **negation-gated**: a phrase immediately preceded by a negator
/// (`not`, `n't`, `non-`, `never`, …) does not corroborate — a docstring that
/// says "this is *not* idempotent" must not raise the idempotence tier.
public enum DocstringPropertyCorroborator {

    /// The algebraic properties a docstring can corroborate. Extensible — adding
    /// a property is a new `case` plus a `vocabulary` row; the wiring in each
    /// template is one signal-function call.
    public enum Property: String, Sendable, Equatable, CaseIterable {
        case idempotence
        case involution
        case commutativity
        case associativity
        case roundTrip
        case monotonicity
    }

    /// A successful corroboration, carrying the matched phrase so the template's
    /// explainability block can quote the prose that raised the tier.
    public struct Corroboration: Sendable, Equatable {
        /// The exact (lowercased) phrase from the vocabulary that matched.
        public let matchedPhrase: String

        public init(matchedPhrase: String) {
            self.matchedPhrase = matchedPhrase
        }
    }

    /// Discriminating assertion phrases per property. Each phrase is matched as a
    /// lowercased substring; a phrase corroborates only when it is present AND not
    /// negated. Phrases are chosen to be *unique* to their property so a match on
    /// one never leaks into another.
    static func vocabulary(for property: Property) -> [String] {
        switch property {
        case .idempotence: return idempotenceVocabulary
        case .involution: return involutionVocabulary
        case .commutativity: return commutativityVocabulary
        case .associativity: return associativityVocabulary
        case .roundTrip: return roundTripVocabulary
        case .monotonicity: return monotonicityVocabulary
        }
    }

    static let idempotenceVocabulary: [String] = [
        "idempotent",
        "idempotence",
        "no further effect",
        "no additional effect",
        "no-op if already",
        "no effect if already",
        "already normalized",
        "already canonical",
        "canonical form",
        "normal form",
        "normalized form",
        "fixed point",
        "applying it twice has no",
        "applying twice has no",
        "second application has no",
        "reapplying has no",
        // The "already X → no-op" mutation-contract idiom (the swift-collections
        // insert/remove idempotence phrasing). Every phrase is self-anchored on
        // "already"/"if present" + a no-change outcome — deliberately NOT the
        // bare "no effect" / "in-place", which document index-limit and mutation
        // behaviour, not idempotence, and would flood false boosts.
        "not already present",
        "not already a member",
        "not already in the set",
        "not already contained",
        "does nothing if already",
        "no change if already",
        "leaves it unchanged if already",
        "if already present, this does nothing",
        "if already a member"
    ]

    static let involutionVocabulary: [String] = [
        "self-inverse",
        "self inverse",
        "own inverse",
        "inverse of itself",
        "undoes itself",
        "is its own inverse",
        "applying it twice returns the original",
        "applying twice returns the original",
        "twice returns the original",
        "twice yields the original",
        "twice restores the original",
        "returns to the original"
    ]

    static let commutativityVocabulary: [String] = [
        "commutative",
        "commutativity",
        "order of the arguments doesn't matter",
        "order of the arguments does not matter",
        "order of the operands doesn't matter",
        "order of the operands does not matter",
        "argument order doesn't matter",
        "argument order does not matter",
        "order-independent",
        "order independent",
        "either order gives the same",
        "same result in either order",
        "symmetric in its arguments",
        "symmetric in both arguments"
    ]

    static let associativityVocabulary: [String] = [
        "associative",
        "associativity",
        "grouping doesn't matter",
        "grouping does not matter",
        "regardless of grouping",
        "regardless of how they are grouped",
        "regardless of how they're grouped",
        "how the operands are grouped doesn't matter",
        "how the arguments are grouped doesn't matter"
    ]

    static let roundTripVocabulary: [String] = [
        "round-trip",
        "round trip",
        "roundtrip",
        "recovers the original",
        "recovers the original value",
        "restores the original value",
        "losslessly",
        "lossless round",
        "encodes and decodes"
    ]

    static let monotonicityVocabulary: [String] = [
        "monotone",
        "monotonic",
        "monotonically",
        "non-decreasing",
        "nondecreasing",
        "order-preserving",
        "order preserving",
        "preserves order",
        "preserves the order",
        "preserves ordering",
        "preserves the ordering"
    ]

    /// Tokens that negate a following assertion. Checked in the window of source
    /// text immediately preceding a matched phrase.
    static let negators: [String] = [
        "not ", "n't ", "non-", "never ", "cannot ", "can not ", "no longer ",
        "isn't", "aren't", "doesn't", "does not ", "won't", "without "
    ]

    /// The character window before a matched phrase scanned for a negator.
    static let negationWindow = 24

    /// Corroborate `property` against `docComment`, or `nil` when the prose does
    /// not (or negates) the assertion.
    public static func corroboration(
        for property: Property,
        in docComment: String?
    ) -> Corroboration? {
        guard let raw = docComment else { return nil }
        let text = raw.lowercased()
        for phrase in vocabulary(for: property) {
            guard let range = text.range(of: phrase) else { continue }
            if isNegated(phraseStart: range.lowerBound, in: text) { continue }
            return Corroboration(matchedPhrase: phrase)
        }
        return nil
    }

    /// `true` when a negator token appears in the window of `text` immediately
    /// before `phraseStart`.
    private static func isNegated(
        phraseStart: String.Index,
        in text: String
    ) -> Bool {
        let windowStart = text.index(
            phraseStart,
            offsetBy: -negationWindow,
            limitedBy: text.startIndex
        ) ?? text.startIndex
        let preceding = text[windowStart ..< phraseStart]
        return negators.contains { preceding.contains($0) }
    }
}
