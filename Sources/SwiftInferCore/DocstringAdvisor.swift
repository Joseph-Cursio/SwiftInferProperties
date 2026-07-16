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
    /// prose. `predicate` alone is the role-entailed law that leaves a hole for
    /// the definition ("it must agree with a reference definition only you can
    /// state"), which is why it is the one that pulls a docstring in.
    public static let referenceDefinitionHungryTemplates: Set<String> = ["predicate"]

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

        // 4. A self-contained role-entailed law already serves the function.
        //    Repeating the docstring would only cost trust. No advisory.
        return nil
    }

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
