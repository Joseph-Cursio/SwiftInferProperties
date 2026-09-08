import SwiftInferCore

/// One answer to "does this body call a non-deterministic API, and which ones".
///
/// There were six. Five templates and one `FunctionSummary` accessor each built the same
/// `.nonDeterministicBody` veto, and **they did not gate on the same thing**: two read
/// `bodySignals.hasNonDeterministicCall` and four read `!bodySignals.nonDeterministicAPIsDetected
/// .isEmpty`. Those are two stored fields encoding one fact. The scanner writes them together —
/// `hasNonDeterministicCall: !scanner.detectedAPIs.isEmpty` beside
/// `nonDeterministicAPIsDetected: scanner.detectedAPIs.sorted()` — but `BodySignals`' public
/// initializer takes them separately, so nothing makes it true, and the two families of veto
/// disagree wherever it is not: the flag-readers raise a veto whose detail line names no API, and
/// the list-readers raise nothing at all.
///
/// Every reader now goes through the list, which is the field that carries the evidence.
///
/// `InversePairTemplate` and `RoundTripTemplate` held byte-identical copies of the pair form,
/// down to the four-arm `describeAffectedSide`.
extension FunctionSummary {

    /// The non-deterministic APIs this body calls, sorted by the scanner.
    ///
    /// Also removes the `bodySignals` hop from the call sites: that a summary keeps its
    /// type-flow signals in a nested value is the summary's business.
    var nonDeterministicAPIs: [String] { bodySignals.nonDeterministicAPIsDetected }

    /// Whether the body calls any of them.
    var callsNonDeterministicAPI: Bool { !nonDeterministicAPIs.isEmpty }
}

extension Signal {

    /// The `.nonDeterministicBody` veto for a group of bodies, or `nil` when every one is clean.
    ///
    /// `detail` receives the sorted union of the APIs found, already joined, so each caller
    /// supplies only the phrase that names what it was scoring.
    static func nonDeterministicVeto(
        acrossBodiesOf summaries: [FunctionSummary],
        detail: (String) -> String
    ) -> Signal? {
        let apis = Set(summaries.flatMap(\.nonDeterministicAPIs)).sorted()
        guard !apis.isEmpty else { return nil }
        return Signal(
            kind: .nonDeterministicBody,
            weight: Signal.vetoWeight,
            detail: detail(apis.joined(separator: ", "))
        )
    }
}

extension FunctionPair {

    /// Which halves call a non-deterministic API, phrased for the veto's detail line.
    var nonDeterministicSideDescription: String {
        switch (forward.callsNonDeterministicAPI, reverse.callsNonDeterministicAPI) {
        case (true, true): "both bodies"
        case (true, false): "\(forward.name) body"
        case (false, true): "\(reverse.name) body"
        case (false, false): "neither body"
        }
    }

    /// The veto raised when either half's body calls a non-deterministic API.
    ///
    /// A pure property of the pair, beside `sharedDiscoverableGroup`, rather than a private static
    /// on each template that happens to score pairs.
    var nonDeterministicVetoSignal: Signal? {
        Signal.nonDeterministicVeto(acrossBodiesOf: [forward, reverse]) {
            "Non-deterministic API in \(nonDeterministicSideDescription): \($0)"
        }
    }
}
