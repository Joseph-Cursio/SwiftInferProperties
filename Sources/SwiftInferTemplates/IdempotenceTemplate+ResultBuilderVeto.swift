import SwiftInferCore

/// Result-builder veto on `IdempotenceTemplate` — `docs/parsing-catalog-gap.md`
/// §8, the other half of the same finding as the pairing filter.
///
/// The pairing filter removes the round-trip and inverse-pair cliques; this
/// removes the idempotence rows on the same methods. They are not *false* —
/// `buildEither(first component: Component) -> Component { component }` is the
/// identity, so `f(f(x)) == f(x)` genuinely holds. They are **unrefutable**,
/// which is the failure this catalog is most explicit about: a law no
/// implementation could fail teaches the reader nothing and spends their
/// attention. Appendix C's rule is to score refutability, not suggestion count.
///
/// Emitted as a veto `Signal` rather than a hard filter so the calibration
/// record is preserved — the same posture `setAlgebraShapeVeto` and
/// `mathForwardFunctionVeto` take. The suggestion still scores; it lands in
/// Suppressed and is filtered from output.
extension IdempotenceTemplate {

    /// Returns a veto `Signal` when the subject is a compiler-called
    /// result-builder method. `nil` otherwise.
    static func resultBuilderVeto(for summary: FunctionSummary) -> Signal? {
        guard ResultBuilderMethods.isBuilderMethod(summary.name) else { return nil }
        return Signal(
            kind: .protocolCoveredProperty,
            weight: Signal.vetoWeight,
            detail: "'\(summary.name)' is a `@resultBuilder` method the compiler "
                + "calls — plumbing, not a transform anyone applies twice. Several "
                + "of them are the identity by construction, so `\(summary.name)"
                + "(\(summary.name)(x)) == \(summary.name)(x)` cannot fail for any "
                + "implementation; an unrefutable law spends the reader's attention "
                + "and teaches nothing"
        )
    }
}
