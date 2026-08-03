import Foundation

/// Per-template render-time phrasing: **one record per law**, and the fourth enumeration of the
/// template vocabulary (after `TemplateName.verifiable`, `resolveFunctionCalls`, and the composer
/// dispatch).
///
/// ## Why a record rather than four switches
///
/// This started as four parallel `switch`es over a `Kind` enum — subject line, forward expression,
/// inverse expression, expected expression — each having to grow a case for every new law. That is
/// the parallel-list shape this repo has been bitten by repeatedly, and it fails silently: a law
/// added to three of the four still renders, just wrongly in one line.
///
/// A record makes the omission a **compile error** instead. `RenderShape` has no default
/// initializer, so a new law cannot be declared without answering all four questions at once.
///
/// ## Why the lookup is a dictionary and its miss is a known defect
///
/// `shape(forTemplate:)` falls back to `.roundTrip`, and that fallback has already shipped wrong
/// output: five templates — `predicate`, `binary-idempotence`, `homomorphism`,
/// `multiplicative-homomorphism`, `measure-non-negativity` — resolved through it, so a passing
/// `predicate` run printed `round-trip contains/contains`, the forward name twice standing in for
/// an inverse the law does not have. Nothing threw; the verdict was simply about a different law.
///
/// The fallback stays because a render must always produce *something*, and
/// `VerifiableTemplateReachTests.everyVerifiableTemplateHasItsOwnVerdictPhrasing` is what makes it
/// safe: it renders every `TemplateName.verifiable` entry and fails on any that comes back phrased
/// as a round trip. That test is how the four beyond `predicate` were found.
struct RenderShape {

    /// The counterexample block's shape. Most laws state an EQUATION — two expressions and a value
    /// they should agree on. Two do not, and neither can be phrased by substituting different
    /// strings into that frame:
    ///
    /// - **`.trap`** (totality) — no second expression and no expected value. The law is *a value
    ///   came back*; the counterexample is a crash, and the fields carry `"trapped"` plus the
    ///   runtime's own message.
    /// - **`.bound`** (measure non-negativity) — compares against a bound, not a value. Its
    ///   composer hardcodes the inverse field to `"0"` precisely because there is no second
    ///   expression to evaluate.
    ///
    /// Forced through the equation frame, a totality refutation read
    /// `f(f(input)) = Swift runtime failure … expected ≈ input (within Int.isApproximatelyEqual)`
    /// — a trap described as a failed approximate comparison — and a negative measure would claim
    /// to be approximately equal to zero.
    enum Framing { case equation, trap, bound }

    typealias Context = VerifyResultRenderer.Context

    let framing: Framing
    let subject: @Sendable (Context) -> String
    let forward: @Sendable (Context) -> String
    let inverse: @Sendable (Context) -> String
    let expected: @Sendable (Context) -> String

    func subjectLine(context: Context) -> String { subject(context) }
    func forwardExpression(context: Context) -> String { forward(context) }
    func inverseExpression(context: Context) -> String { inverse(context) }
    func expectedExpression(context: Context) -> String { expected(context) }

    /// The counterexample / advisory value block, owned by the shape because two of the three
    /// framings are not the equation block with different strings in it.
    ///
    /// `forward` and `inverse` are the two fields `DefaultFailDetail` carries, and each framing
    /// reads them under the names its own composer wrote them with. Nothing is re-derived here.
    func valueLines(
        input: String,
        forward forwardValue: String,
        inverse inverseValue: String,
        context: Context
    ) -> [String] {
        let shown = VerifyResultRenderer.displayValue(input)
        switch framing {
        case .trap:
            return [
                "    input  = \(shown)",
                "    \(context.forwardName)(input) did not return — it trapped",
                "    runtime: \(VerifyResultRenderer.displayValue(inverseValue))"
            ]

        case .bound:
            return [
                "    input  = \(shown)",
                "    \(forward(context)) = \(VerifyResultRenderer.displayValue(forwardValue))",
                "    expected  \(expected(context))"
            ]

        case .equation:
            return [
                "    input  = \(shown)",
                "    \(forward(context)) = \(VerifyResultRenderer.displayValue(forwardValue))",
                "    \(inverse(context)) = \(VerifyResultRenderer.displayValue(inverseValue))",
                "    expected ≈ \(expected(context)) "
                    + "(within \(context.carrierType).isApproximatelyEqual)"
            ]
        }
    }
}

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
        "measure-non-negativity": .measureNonNegativity
    ]
}
