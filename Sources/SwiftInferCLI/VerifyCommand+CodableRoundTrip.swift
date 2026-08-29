import Foundation
import SwiftInferCore

// Codable-round-trip's carrier-only verify resolution, split out of
// `VerifyCommand+TemplateDispatch` to keep that file under the length cap.
extension SwiftInferCommand.Verify {

    /// The `idempotence-lifted` / `monotonicity` single-function resolution,
    /// extracted from `resolveFunctionCalls`'s switch to keep its body under the
    /// length cap. Monotonicity's OC composer also needs the un-stripped
    /// `primaryFunctionName` (e.g. `"index(after:)"`) to recover the labeled arg,
    /// and the RAW rendered call to read a method name off; the value composer
    /// reads only `functionCalls.first`, which is now the LABELLED form.
    static func liftedOrMonotonicityCalls(
        entry: SemanticIndexEntry,
        typeQualifier: String,
        funcName: String
    ) -> ResolvedCalls {
        let call = CallExpressionShape.render(typeQualifier: typeQualifier, bareFunctionName: funcName)
        // **This resolver was the ONE arm that never wrapped the call.** V1.149 added
        // `labeledCallExpression` and `singleCallResolved` routes every other template
        // through it; these two went on rendering the bare reference, so a subject with an
        // external argument label emitted `wordCount(value)` against
        // `wordCount(forScale:)`.
        //
        // **Measured on `swift-collections` @ `899809d3`**: 7 of 64 `monotonicity` rows
        // failed with `missing argument label` — `'forScale:'` ×5, `'forOffset:'`,
        // `'remaining:'` (`docs/measurements/monotonicity-verify-reach.md` §5). Two more
        // rows failed the same way on OpenAPIKit, recorded there as a single line in an
        // error histogram.
        let labeled = labeledCallExpression(
            primaryFunctionName: entry.primaryFunctionName,
            reference: call
        )
        // The OC/instance composer needs the RAW reference as well as the labelled one: it
        // reads a method name off it with `split(".").last`, which a closure literal has no
        // meaningful answer for. So monotonicity carries three elements — labelled call,
        // un-stripped `primaryFunctionName`, raw call — and the two composers take the one
        // they can use. `idempotence-lifted` applies its call positionally and takes the
        // labelled form alone.
        let expressions = entry.templateName == "monotonicity"
            ? [labeled, entry.primaryFunctionName, call]
            : [labeled]
        return ResolvedCalls(
            expressions: expressions,
            rendererForwardName: call,
            rendererInverseName: call
        )
    }

    /// Resolve the codable-round-trip verify calls. There is **no**
    /// forward/inverse function pair — the oracle is the carrier's own `Codable`
    /// conformance exercised through JSON, so the composer
    /// (`StrategistDispatchEmitter.composeCodableRoundTripPass`) needs only the
    /// carrier (resolved from `typeShape`). Empty `expressions`; the renderer
    /// names the two custom halves for display.
    static func resolveCodableRoundTripCalls(
        entry: SemanticIndexEntry,
        carrier: String
    ) throws -> ResolvedCalls {
        try requireEquatableCodableCarrier(entry: entry, carrier: carrier)
        return ResolvedCalls(
            expressions: [],
            rendererForwardName: "encode(to:)",
            rendererInverseName: "init(from:)"
        )
    }

    /// Gate a codable-round-trip carrier on `Equatable`. Conservative: only
    /// throws when the entry carries a `typeShape` whose inheritance clause
    /// *definitively* lacks `Equatable` / `Hashable` (Hashable refines
    /// Equatable). A nil `typeShape` (external / unindexed carrier) is left to
    /// the strategist's own coverage handling — never false-gate a carrier whose
    /// conformance we can't see (e.g. `Equatable` added in an extension). A
    /// thrown `VerifyError` maps to architectural-coverage-pending, not a doomed
    /// build.
    static func requireEquatableCodableCarrier(
        entry: SemanticIndexEntry,
        carrier: String
    ) throws {
        guard let shape = entry.typeShape else { return }
        let equatableLike: Set<String> = ["Equatable", "Hashable"]
        guard shape.inheritedTypes.contains(where: { equatableLike.contains($0) }) else {
            throw VerifyError.unsupportedCarrier(
                carrier: carrier,
                expected: [
                    "codable-round-trip needs \(carrier) to be Equatable "
                        + "to compare decode(encode(x)) == x"
                ]
            )
        }
    }
}
