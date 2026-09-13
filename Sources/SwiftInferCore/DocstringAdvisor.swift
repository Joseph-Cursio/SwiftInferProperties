import Foundation

/// What the docstring advisory decided to say about one documented function.
///
/// A docstring earns a place in the output only as a **reference definition** —
/// the sentence a law is checked *against*. There are exactly two shapes that
/// pays off, and both are gated on the prose actually being a contract:
///
/// - `.referenceDefinition` — the tool proposed a law that *openly owes* an
///   external spec (a `predicate` "must agree with a reference definition only
///   you can state"; a lifted example test that needs the sentence it
///   generalizes). The docstring is that spec. This is the aligned-with-
///   TestLifter case: an example plus a documented definition is a refutable
///   property; either alone is not.
/// - `.fallbackContract` — the templates could offer nothing a correct
///   implementation is *owed* (only a `determinism` tautology, or refutable-but-
///   not-role-entailed red herrings like associativity on a function that is not
///   a monoid). Here the documented sentence is the only refutable contract on
///   the function, so it is surfaced as the law of last resort.
///
/// A function whose law is already self-contained and role-entailed — a
/// `comparator`'s strict weak ordering, a `partition`'s tiling — gets **no**
/// advisory: the tool already handed the reader something owed, and repeating
/// the docstring would only spend trust.
public enum DocstringAdvisory: Sendable, Equatable {

    case referenceDefinition(ReferenceDefinition)
    case fallbackContract(FallbackContract)
    case complementaryContract(ComplementaryContract)

    /// The docstring, attached to a proposed law that owes a reference definition.
    public struct ReferenceDefinition: Sendable, Equatable {
        /// The reflowed docstring prose.
        public let docComment: String
        /// The template of the law the definition attaches to (e.g. `"predicate"`,
        /// or the lifted template when `fromLiftedTest`).
        public let template: String
        /// `true` when the law was lifted from an example test (TestLifter) — the
        /// synergy case, where the example supplies the witness and the docstring
        /// supplies the definition it generalizes to.
        public let fromLiftedTest: Bool

        public init(docComment: String, template: String, fromLiftedTest: Bool) {
            self.docComment = docComment
            self.template = template
            self.fromLiftedTest = fromLiftedTest
        }
    }

    /// The docstring, surfaced beside a role-entailed law that is **owed but not
    /// reachable** — so it does not discharge the sentence.
    ///
    /// The third shape, and the reason it exists is that neither of the other two
    /// could say this without lying. `.referenceDefinition` claims the law *owes*
    /// an external spec: `input-totality` owes nothing, its claim is "does not
    /// trap". `.fallbackContract` calls what fired a guess "a correct
    /// implementation need not satisfy": `input-totality` is role-entailed and a
    /// correct implementation must satisfy it. Both are true sentences about
    /// other templates and false about this one.
    public struct ComplementaryContract: Sendable, Equatable {
        /// The reflowed docstring prose.
        public let docComment: String

        /// The role-entailed templates that fired and did not discharge it. Sorted,
        /// de-duplicated.
        public let servedBy: [String]

        public init(docComment: String, servedBy: [String]) {
            self.docComment = docComment
            self.servedBy = servedBy
        }
    }

    /// The docstring, surfaced as the only refutable contract on a function the
    /// templates left with nothing role-entailed.
    public struct FallbackContract: Sendable, Equatable {
        /// The reflowed docstring prose.
        public let docComment: String
        /// The refutable-but-not-role-entailed templates that *did* fire, named so
        /// the advisory can say "these matched by shape, but none is owed — the
        /// sentence is." Empty when nothing fired at all (pure determinism
        /// fallback). Sorted, de-duplicated.
        public let redHerrings: [String]

        public init(docComment: String, redHerrings: [String]) {
            self.docComment = docComment
            self.redHerrings = redHerrings
        }
    }
}

/// Decides whether a documented function's docstring should be surfaced as a
/// reference definition, and in which of the two shapes.
///
/// Pure and side-effect-free: it reads a function's docstring and the
/// suggestions already proposed for it, and returns a `DocstringAdvisory?`.
/// Rendering and wiring live at the call site.
public enum DocstringAdvisor {

    /// Templates whose law **explicitly owes an external reference definition**
    /// the tool cannot state on its own. A documented sentence is exactly that,
    /// so the docstring attaches here.
    ///
    /// Deliberately *not* every role-entailed template: a `comparator`'s strict
    /// weak ordering and a `partition`'s tiling are fully specified by the
    /// template itself — they are owed *and* self-contained, so they need no
    /// prose. `predicate` is the role-entailed law that leaves a hole for the
    /// definition ("it must agree with a reference definition only you can
    /// state"), which is why it pulls a docstring in.
    ///
    /// `comparator` joins it — but for a subtler reason (B25 follow-on). The
    /// strict-weak-ordering law is self-contained as a *validity* check, and
    /// verifies the comparator is *a* valid ordering. It says nothing about
    /// *which* ordering: a comparator that sorts by the wrong key (name length
    /// where the docstring says lexicographic) is a perfectly valid strict weak
    /// order and passes the SWO law clean. The docstring states the intended key;
    /// that is a reference definition the SWO law cannot capture, so the
    /// ordering-key oracle rides alongside it.
    public static let referenceDefinitionHungryTemplates: Set<String> = ["predicate", "comparator"]

    /// The advisory for one function, or `nil` for no advisory.
    ///
    /// - Parameters:
    ///   - docComment: the function's reflowed docstring, or `nil`.
    ///   - suggestions: every suggestion proposed for *this* function.
    public static func advisory(
        forFunctionWith docComment: String?,
        suggestions: [Suggestion]
    ) -> DocstringAdvisory? {
        // The refutability gate on the prose itself: a docstring earns a place
        // only when it states a checkable contract, not when it narrates context.
        guard let doc = docComment, isContract(doc) else { return nil }

        // 1. A proposed law openly owes a reference definition → the docstring is it.
        if let hungry = suggestions.first(where: {
            referenceDefinitionHungryTemplates.contains($0.templateName)
        }) {
            return .referenceDefinition(
                .init(docComment: doc, template: hungry.templateName, fromLiftedTest: false)
            )
        }

        // 2. A law lifted from an example test → the docstring is the sentence it
        //    generalizes. This is the synergy case TestLifter sets up.
        if let lifted = suggestions.first(where: { $0.liftedOrigin != nil }) {
            return .referenceDefinition(
                .init(docComment: doc, template: lifted.templateName, fromLiftedTest: true)
            )
        }

        // 3. Nothing refutable AND role-entailed survived — the reader would be
        //    handed only a tautology or red herrings. The sentence is the law.
        if !suggestions.contains(where: Refutability.isWorthSurfacingBelowCut) {
            let redHerrings = Set(
                suggestions.filter(Refutability.isRefutable).map(\.templateName)
            ).sorted()
            return .fallbackContract(.init(docComment: doc, redHerrings: redHerrings))
        }

        // 4. Every role-entailed law that fired is one no realistic generator reaches, so
        //    nothing the reader was handed actually checks what the docstring claims. The
        //    sentence stands beside it rather than instead of it.
        let serving = suggestions.filter(Refutability.isWorthSurfacingBelowCut)
        if serving.allSatisfy({ unreachableByRealisticInputTemplates.contains($0.templateName) }) {
            return .complementaryContract(
                .init(docComment: doc, servedBy: Set(serving.map(\.templateName)).sorted())
            )
        }

        // 5. A self-contained role-entailed law already serves the function.
        //    Repeating the docstring would only cost trust. No advisory.
        return nil
    }

    /// Role-entailed templates whose **counterexamples a realistic generator never produces**, so
    /// the law being owed does not mean the reader has been served.
    ///
    /// **Owed is not the same as informative, and arm 5 assumed it was.** Its premise — repeating
    /// a docstring beside a law that already serves the function costs trust — is right. What
    /// broke is the "already serves": `input-totality`'s claim is *does not trap*, and its own
    /// caveat list says so in capitals — *"A GENERATOR OF REALISTIC INPUT WILL NEVER FIND THIS.
    /// The counterexamples live in malformed input."* A law reachable only by deliberately
    /// malformed bytes says nothing about whether the parse is *right*, which is what the
    /// docstring states.
    ///
    /// The cost was total rather than partial, because `input-totality` fires on every
    /// interpretation verb — that is its trigger. So for the whole parse / decode / read family,
    /// arm 5 always won and the reference-definition advisory could never fire
    /// (SwiftInferProperties#420). Measured over SwiftMarkdownWiki: four of four `input-totality`
    /// subjects suppressed, three of them carrying contract-cue docstrings.
    ///
    /// **The suppressed sentences were worth having.** `FrontMatter.parse`'s docstring says "YAML
    /// front matter"; turning that word into a law — the three YAML sequence spellings must agree
    /// — found a live bug, `tags: [math, demo]` parsing to `["[math", "demo]"]`, brackets
    /// included, in a vault the repository ships. The tool had the docstring, classified it as a
    /// contract, and declined to print it.
    ///
    /// One entry, deliberately. `normal-form` is the neighbouring candidate and is **not** here:
    /// `print(parse(print(parse(s)))) == print(parse(s))` is checked by ordinary input and does
    /// constrain what the parse means. Widening this set on no evidence is how the approximations
    /// this file already records got written.
    public static let unreachableByRealisticInputTemplates: Set<String> = ["input-totality"]

    /// Whether a docstring states a refutable **contract** — a checkable claim
    /// about the result — rather than merely **narrating** context or purpose.
    ///
    /// A deliberately conservative keyword heuristic, in the same spirit as
    /// `Refutability`'s template sets and the tool's precision-over-recall
    /// posture: a sentence must carry at least one contract cue to qualify, and
    /// a purely narrative doc (only "helper", "used by", "convenience", …) does
    /// not. False negatives (a real contract phrased unusually) cost a missed
    /// advisory; false positives cost a reader's trust, so the gate leans strict.
    static func isContract(_ doc: String) -> Bool {
        let lower = doc.lowercased()
        return contractCues.contains { lower.contains($0) }
    }

    /// Phrases that signal a checkable claim about the output relative to the
    /// input: result verbs, quantifiers and bounds, and relational guarantees.
    private static let contractCues: [String] = [
        // Result verbs — the doc says what the function DOES to produce its value.
        "returns", "return the", "return a", "computes", "produces", "yields",
        "rounds", "orders", "sorts", "maps", "converts", "normalizes", "normalises",
        "clamps", "caps", "capped", "encodes", "decodes", "parses", "reverses",
        // Quantifiers and bounds — a claim over all inputs, or on the value's range.
        "never", "always", "every", "each", "at most", "at least", "no more than",
        "no fewer", "no less", "exactly", "non-negative", "nonnegative", "no larger",
        "no smaller", "nearest", "ties", "ascending", "descending", "in order",
        "sorted", "unique", "no duplicates", "non-empty", "nonempty", "contains no",
        "monotonic", "idempotent",
        // Relational guarantees — the value equals / matches / inverts something.
        "inverse", "round-trip", "round trip", "roundtrip", "preserves", "the same",
        "equal to", "equals", "matches", "must ", "is valid when", "if and only if"
    ]
}
