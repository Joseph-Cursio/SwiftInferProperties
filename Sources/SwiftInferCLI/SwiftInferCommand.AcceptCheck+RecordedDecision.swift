import Foundation

extension SwiftInferCommand.AcceptCheck {

    /// `accept-check`'s detail for a template verify does not measure by a recorded decision
    /// (`DeliberateVerifyDecline`), or nil for any other error.
    ///
    /// `.error` is the only one of the four kinds that fits — it already means "no verdict on
    /// this run, out of the rate's denominator" — but the detail says WHY, so a law `accept`
    /// wrote does not read as a tool failure on every re-check. A decline and a deferral get
    /// different details: a planned composer is not a refusal, and filed as one it read as a
    /// law verify will never measure.
    ///
    /// Split out of `checkOne` so its catch list stays under the cyclomatic cap.
    static func recordedDecisionDetail(for error: VerifyError) -> String? {
        switch error {
        case let .declinedByDesign(_, reason):
            "not measured by verify, by design: \(reason)"

        case let .deferredComposer(_, reason):
            "verify composer planned, not built yet: \(reason)"

        default:
            nil
        }
    }
}
