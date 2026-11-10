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
                "    runtime: \(VerifyResultRenderer.displayValue(inverseValue))",
            ]

        case .bound:
            return [
                "    input  = \(shown)",
                "    \(forward(context)) = \(VerifyResultRenderer.displayValue(forwardValue))",
                "    expected  \(expected(context))",
            ]

        case .equation:
            return [
                "    input  = \(shown)",
                "    \(forward(context)) = \(VerifyResultRenderer.displayValue(forwardValue))",
                "    \(inverse(context)) = \(VerifyResultRenderer.displayValue(inverseValue))",
                "    expected ≈ \(expected(context)) "
                    + "(within \(context.carrierType).isApproximatelyEqual)",
            ]
        }
    }
}
