import Foundation

/// A generator the law needs, written out so the reader can run it.
///
/// ## Why a template must ship its generator, and not merely describe one
///
/// A law and the inputs it is checked against are **one artefact**. Stating the law and leaving the
/// generator to the reader looks like a division of labour and is not: for a large class of real
/// bugs, a uniform generator makes the law pass *vacuously*, and the reader who writes the obvious
/// generator learns nothing and concludes the code is fine.
///
/// This is not a hypothesis. On the road-test fixture the only bug the loop reliably surfaces —
/// a listing predicate that strips **every** occurrence of a path prefix rather than the leading one —
/// is invisible to a generator drawing strings from a wide alphabet, because such a generator
/// essentially never produces a path in which the parent path *recurs*. Three independent readers
/// found the bug, and all three found it the same way: they read a caveat that told them to shrink
/// the alphabet, and then **hand-wrote the generator themselves**. One measured 5341 failures in
/// 20000 inputs once they did; with a wide alphabet the same law passes clean.
///
/// So the template knew the generator the law needed, printed it as English, and made the reader
/// re-derive it. That is the same failure as a linter that prints a finding it never seeds: the
/// knowledge is in the tool and does not reach the work.
///
/// ## The principle
///
/// **A law that distinguishes two notions which usually coincide will pass vacuously under a uniform
/// generator.** `isImmediateChild` confuses "strip the prefix" with "strip every occurrence" — and
/// those two agree on every input where the prefix occurs exactly once, which is almost every input a
/// wide alphabet produces. The counterexample lives in the collisions, and collisions have to be
/// *manufactured*: shrink the universe until values repeat.
///
/// That is what `CollisionBias` builds, and what this type carries to the reader.
public struct GeneratorRecipe: Sendable, Equatable {

    /// The parameter this generator feeds — `path`, `index`.
    public let subject: String

    /// The Swift type it produces.
    public let typeName: String

    /// Runnable Swift, in the kit's `Gen` idiom. Paste-able into a property test.
    public let expression: String

    /// **Why this bias rather than the obvious one.** Not decoration: a reader who does not
    /// understand why the alphabet is small will widen it back on the first cleanup pass, and the law
    /// will go quiet without anyone noticing it stopped testing anything.
    public let rationale: String

    public init(subject: String, typeName: String, expression: String, rationale: String) {
        self.subject = subject
        self.typeName = typeName
        self.expression = expression
        self.rationale = rationale
    }
}

/// The generator vocabulary for laws whose counterexamples live in **collisions**.
///
/// Every recipe here answers one question: *what has to repeat before this law can fail?* A uniform
/// generator answers "nothing", which is why it finds nothing.
public enum CollisionBias {

    /// The alphabet. Three symbols, and the number is the whole point.
    ///
    /// With a wide alphabet the probability that a generated path contains its own parent as an
    /// interior component is vanishingly small, so a predicate that confuses *prefix* with *every
    /// occurrence* agrees with the correct answer on essentially every input. Shrink the alphabet to
    /// three and the collision becomes common — `/a/b/a/c` is now an ordinary draw rather than a
    /// once-in-a-billion accident.
    public static let alphabet = ["a", "b", "c"]

    /// Strings over a tiny alphabet **that includes the separator**, so substrings repeat and — for
    /// anything path-shaped — a parent recurs inside its own descendants.
    ///
    /// **Deliberately not a "path generator".** A template cannot know whether a `String` parameter
    /// is a path, a filename, a key or a query, and a generator that assumed *path* would hand a
    /// search predicate `/a/b/c` and call it a day. What generalises is not the shape but the
    /// **alphabet**: draw from three symbols, one of which is a separator, and structure collides
    /// whatever the domain. `"/a/b/a"` and `"aba"` both fall out, and both are collisions.
    ///
    /// Includes the degenerate values on purpose: `"/"` — the root, where *strip the prefix* and
    /// *strip every occurrence* diverge most violently, because stripping `/` deletes **every**
    /// separator and collapses any path to a single component — and `""`.
    public static func collidingString(subject: String) -> GeneratorRecipe {
        return GeneratorRecipe(
            subject: subject,
            typeName: "String",
            expression: collidingStringExpression,
            rationale: "A four-symbol alphabet including the separator, so substrings REPEAT and any "
                + "path contains its own ancestors. A wide alphabet never produces that, and a "
                + "predicate that confuses `strip the prefix` with `strip every occurrence` agrees "
                + "with the right answer everywhere the two coincide — which is everywhere, until "
                + "they collide. Do not widen this alphabet."
        )
    }

    /// The colliding-string generator, as runnable `swift-property-based` Swift.
    ///
    /// **Every construct here compiles against the vendored kit, and that is not incidental — it is
    /// the whole point of shipping a generator instead of describing one.** Walk 6 caught the earlier
    /// version emitting `Gen.frequency` (which is `@available(swift 6.2)`) and `Gen.array(of:count:)`
    /// (a *static* form the kit does not have — it has only an instance `.array(of:)`), so every cold
    /// reader had to hand-re-implement it. This version uses only what exists in every language mode:
    /// `Gen<String?>.element(of:)`, instance `.array(of:)`, and `.map`.
    ///
    /// The degenerate `"/"` case is not a separate weighted arm any more; it falls out for free when
    /// the array draws **zero** components (`"/" + [].joined()` is `"/"`), which happens often over
    /// `0...6`. That removes the need for `frequency` without losing the case that matters most — the
    /// root, where a strip-all and a strip-prefix diverge worst.
    private static let collidingStringExpression: String = {
        let symbols = (alphabet + ["/"]).map { "\"\($0)\"" }.joined(separator: ", ")
        return """
            // A FOUR-symbol alphabet, one of which is the separator, so substrings repeat and any
            // path contains its own ancestors — the recurrence a wide alphabet never produces.
            // Zero components yields "/", the root case, for free.
            Gen<String?>.element(of: [\(symbols)] as [String])
                .map { $0! }
                .array(of: 0...6)
                .map { "/" + $0.joined() }
            """
    }()

    /// **The collision is often between a parameter and the carrier's STATE, and a generator that
    /// varies only the parameter cannot produce it.**
    ///
    /// This is not a corner case; it is the road-test's own shape. A reader who extracts
    ///
    ///     struct ImmediateChildPredicate { let currentPath: String
    ///                                      func isImmediateChild(_ path: String) -> Bool }
    ///
    /// has put one half of the collision in a parameter and the other in a stored property. Generate
    /// `path` from a small alphabet and hold `currentPath` fixed at some plausible `"/Documents/"`,
    /// and the parent never recurs inside the child — the law passes, and the bug is untouched.
    /// **Both halves have to be drawn from the same small universe.**
    public static func carrierState(typeName: String) -> GeneratorRecipe {
        // Do NOT emit `\(typeName).gen()` — that method does not exist, and walk 6 caught it not
        // compiling. The template cannot know the carrier's initialiser, so it ships the runnable
        // half (a colliding *String* for the carrier's path-like state) and names the one manual
        // step: feed it into the carrier's own init. Compiles; honest about the seam it cannot cross.
        GeneratorRecipe(
            subject: "\(typeName) (the carrier's own state)",
            typeName: typeName,
            expression: """
                // Draw the CARRIER's String state from the SAME colliding alphabet, then build the
                // carrier from it — e.g. `.map { \(typeName)(currentPath: $0) }` for whatever its
                // path-like stored property is called. Holding that state fixed while varying only
                // the arguments cannot produce the collision, and the collision is the counterexample.
                \(collidingStringExpression)
                """,
            rationale: "Half the collision lives in the carrier's stored state. A generator that "
                + "varies only the arguments, against a carrier fixed at some plausible value, "
                + "quantifies over exactly the inputs where the two notions agree — so the carrier's "
                + "own String state must be drawn from this same generator, not a wide one."
        )
    }

    /// An index that is **allowed to be wrong** — negative, and past the end.
    ///
    /// The interesting values are the ones the code did not expect, and a generator over `0..<count`
    /// asserts the totality clause against exactly the inputs that were never in doubt. A negative
    /// index is what a corrupt server counter supplies, and `dropFirst(negative)` traps.
    public static func outOfRangeIndex(subject: String) -> GeneratorRecipe {
        GeneratorRecipe(
            subject: subject,
            typeName: "Int",
            expression: """
                // NEGATIVE and PAST-THE-END on purpose. Generating `0..<count` would check totality
                // against precisely the indices that were never in question.
                Gen<Int>.int(in: -50...500)
                """,
            rationale: "Totality is a claim about the indices the code did NOT expect. A generator "
                + "bounded to the valid range cannot refute it. A negative index is exactly what a "
                + "corrupt resume counter supplies, and `dropFirst(negative)` traps rather than "
                + "returning nothing."
        )
    }

    /// Keys drawn from a small universe, so **ties actually occur**.
    ///
    /// A comparator's hardest clause — transitivity of *incomparability* — is unreachable without
    /// pairs that compare equal. Over a wide key space a strict weak ordering is never exercised on
    /// the one clause hand-written tests also never check, and the law passes for the wrong reason.
    public static func tiedKeys(subject: String, typeName: String) -> GeneratorRecipe {
        let elements = alphabet.map { "\"\($0)\"" }.joined(separator: ", ")
        return GeneratorRecipe(
            subject: subject,
            typeName: typeName,
            expression: """
                // A SMALL key universe, so pairs compare EQUAL often. Transitivity of incomparability
                // — the clause a folders-first comparator most often breaks, and the one hand-written
                // tests never reach — is vacuous without ties.
                Gen<String?>.element(of: [\(elements)] as [String]).map { $0! }
                """,
            rationale: "Ties are the point. Over a wide key space two values are essentially never "
                + "incomparable, so the transitivity-of-incomparability clause is checked against no "
                + "input that could break it."
        )
    }
}
