import Foundation

// MARK: - The laws

extension RenderShape {

    /// `codable-round-trip` shares this phrasing deliberately — it is a round trip, through a
    /// JSON codec rather than a curated inverse.
    static let roundTrip = RenderShape(
        framing: .equation,
        subject: { "round-trip \($0.forwardName)/\($0.inverseName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(input) " },
        inverse: { "\($0.inverseName)(\($0.forwardName)(input))" },
        expected: { _ in "input" }
    )

    static let idempotence = RenderShape(
        framing: .equation,
        subject: { "idempotence on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(input) " },
        inverse: { "\($0.forwardName)(\($0.forwardName)(input))" },
        expected: { _ in "f(input)" }
    )

    static let commutativity = RenderShape(
        framing: .equation,
        subject: { "commutativity on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(lhs, rhs) " },
        inverse: { "\($0.forwardName)(rhs, lhs)" },
        expected: { "\($0.forwardName)(rhs, lhs)" }
    )

    static let associativity = RenderShape(
        framing: .equation,
        subject: { "associativity on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(\($0.forwardName)(a, b), c) " },
        inverse: { "\($0.forwardName)(a, \($0.forwardName)(b, c))" },
        expected: { "\($0.forwardName)(a, \($0.forwardName)(b, c))" }
    )

    static let idempotenceLifted = RenderShape(
        framing: .equation,
        subject: { "idempotence-lifted on \($0.forwardName) over [\($0.carrierType)]" },
        forward: { "\($0.forwardName)(xs) " },
        inverse: { "\($0.forwardName)(\($0.forwardName)(xs))" },
        expected: { "\($0.forwardName)(xs)" }
    )

    static let dualStyleConsistency = RenderShape(
        framing: .equation,
        subject: {
            "dual-style-consistency on \($0.forwardName)/\($0.inverseName) over \($0.carrierType)"
        },
        forward: { "\($0.forwardName)(x) " },
        inverse: { "{ var copy = x; copy.\($0.inverseName)(); return copy }()" },
        expected: { "\($0.forwardName)(x)" }
    )

    static let monotonicity = RenderShape(
        framing: .equation,
        subject: { "monotonicity on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(a) " },
        inverse: { "\($0.forwardName)(b)" },
        expected: { _ in "f(a) ≤ f(b) when a ≤ b" }
    )

    /// Differential equivalence — `reference(x) == variant(x)`.
    ///
    /// The two expressions take the **same** input rather than nesting, which
    /// is the whole difference from `.roundTrip` and the reason this record
    /// exists: routed through the round-trip fallback, a refutation would have
    /// rendered `variant(reference(input)) … expected input`, a nesting the law
    /// never states and a value it never mentions.
    ///
    /// `expected` is the reference's own result, because that is what the law
    /// says the variant should have produced. Note what this does NOT claim:
    /// the law is symmetric and is silent about which side is wrong. Naming the
    /// reference as "expected" reflects which one the reader is likely to be
    /// changing, not a verdict — the caveats carry that, and the composer
    /// prints both results so the reader can decide.
    static let differentialEquivalence = RenderShape(
        framing: .equation,
        subject: {
            "differential equivalence of \($0.inverseName) against \($0.forwardName) "
                + "over \($0.carrierType)"
        },
        forward: { "\($0.forwardName)(input) " },
        inverse: { "\($0.inverseName)(input)" },
        expected: { "\($0.forwardName)(input)" }
    )

    static let involution = RenderShape(
        framing: .equation,
        subject: { "involution on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(input) " },
        inverse: { "\($0.forwardName)(\($0.forwardName)(input))" },
        expected: { _ in "input" }
    )

    /// Totality — `predicate`. The `.trap` framing never asks for `inverse` or `expected`; both
    /// are spelled as admissions rather than plausible-looking equations, so a future caller that
    /// does reach them gets a sentence instead of a wrong law.
    static let totality = RenderShape(
        framing: .trap,
        subject: { "totality of \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(input) " },
        inverse: { _ in "(totality states no second expression)" },
        expected: { _ in "(totality expects no particular value — only that one was returned)" }
    )

    static let binaryIdempotence = RenderShape(
        framing: .equation,
        subject: { "binary-idempotence on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(x, x) " },
        inverse: { _ in "x" },
        expected: { _ in "x" }
    )

    /// The generated law draws ARRAYS and the carrier recorded on the entry is the element type —
    /// `composeHomomorphismPass` wraps the element generator in `.array(of:)`, the same idiom
    /// `idempotence-lifted` uses and the same reason this prints `[T]`.
    static let homomorphism = RenderShape(
        framing: .equation,
        subject: { "homomorphism on \($0.forwardName) over [\($0.carrierType)]" },
        forward: { "\($0.forwardName)(a + b) " },
        inverse: { "\($0.forwardName)(a) + \($0.forwardName)(b)" },
        expected: { "\($0.forwardName)(a) + \($0.forwardName)(b)" }
    )

    /// Carrier is fixed at `Int`: the composer bounds its own operands to ±10_000 so the product
    /// cannot overflow, and ignores the derived recipe entirely.
    static let multiplicativeHomomorphism = RenderShape(
        framing: .equation,
        subject: { "multiplicative-homomorphism on \($0.forwardName) over Int" },
        forward: { "\($0.forwardName)(a * b) " },
        inverse: { "\($0.forwardName)(a) * \($0.forwardName)(b)" },
        expected: { "\($0.forwardName)(a) * \($0.forwardName)(b)" }
    )

    /// The `≥` is why this cannot go through the equation frame: `expected ≈ 0` would say the
    /// measure should BE zero, when what the law says is that it must not fall below it.
    static let measureNonNegativity = RenderShape(
        framing: .bound,
        subject: { "measure-non-negativity on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(input) " },
        inverse: { _ in "(non-negativity states no second expression)" },
        expected: { _ in "≥ 0" }
    )

    /// Like `measure-non-negativity`, the law is a **predicate on the result** rather than an
    /// equation between two expressions, so it takes the bound framing. The `expected` slot
    /// carries the law in words because the predicate itself is supplied per role — there is no
    /// single expression to print, and printing `≥ 0`'s equivalent for ten different roles would
    /// be a phrasing that fits none of them.
    static let rolePostcondition = RenderShape(
        framing: .bound,
        subject: { "role-postcondition on \($0.forwardName) over \($0.carrierType)" },
        forward: { "\($0.forwardName)(input) " },
        inverse: { _ in "(a postcondition states no second expression)" },
        expected: { _ in "satisfies the role's guarantee" }
    )

    /// Template name → phrasing. A dictionary rather than a `switch` so adding a law costs one
    /// row and no control flow; `round-trip` and `codable-round-trip` share a value on purpose.
    ///
    /// Absence is the defect `everyVerifiableTemplateHasItsOwnVerdictPhrasing` looks for — see
    /// this type's doc comment for what a miss actually printed.
    static let byTemplateName: [String: RenderShape] = [
        "round-trip": .roundTrip,
        "codable-round-trip": .roundTrip,
        "idempotence": .idempotence,
        "commutativity": .commutativity,
        "associativity": .associativity,
        "idempotence-lifted": .idempotenceLifted,
        "dual-style-consistency": .dualStyleConsistency,
        "monotonicity": .monotonicity,
        "involution": .involution,
        "predicate": .totality,
        "binary-idempotence": .binaryIdempotence,
        "homomorphism": .homomorphism,
        "multiplicative-homomorphism": .multiplicativeHomomorphism,
        "measure-non-negativity": .measureNonNegativity,
        "differential-equivalence": .differentialEquivalence,
        "role-postcondition": .rolePostcondition,
    ]
}
