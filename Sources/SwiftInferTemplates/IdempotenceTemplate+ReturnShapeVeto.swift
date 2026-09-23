import SwiftInferCore

/// The veto for a `T -> T` function whose returned expression **builds around**
/// its input instead of projecting out of it.
///
/// See `Signal.Kind.returnExtendsInput` for the measurement and
/// `IdempotenceReturnShape` for why only the return expression is read.
extension IdempotenceTemplate {

    /// A veto when the body's returned expression extends its input, `nil`
    /// otherwise — including when the shape was never computed (`nil` for any
    /// summary that is not a unary endomorphism, and for synthetic summaries).
    ///
    /// **Positive detection only.** `.notExtending` is not a claim that the
    /// function is idempotent, so it must not become a positive signal; absence
    /// of a reason to veto is not evidence for the law.
    static func returnShapeVeto(for summary: FunctionSummary) -> Signal? {
        if case let .reappliesItsRewrite(witness) = summary.bodySignals.idempotenceReturnShape {
            return Signal(
                kind: .returnExtendsInput,
                weight: Signal.vetoWeight,
                detail: "The body is a replacement chain whose output re-enters its own patterns, so "
                    + "\(summary.name) applied twice rewrites again — evaluated on \"\(witness)\", "
                    + "f(f(x)) differs from f(x). The law is false rather than unlikely"
            )
        }
        guard case let .extendsInput(via) = summary.bodySignals.idempotenceReturnShape else {
            return nil
        }
        return Signal(
            kind: .returnExtendsInput,
            weight: Signal.vetoWeight,
            detail: "The returned expression builds around its input (\(via)), so "
                + "\(summary.name)(\(summary.name)(x)) applies the construction twice — "
                + "the law is false rather than unlikely"
        )
    }
}
