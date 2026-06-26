import Foundation

/// The `carrierType` an emitter's `Inputs` carries — the one field
/// `CarrierStubDispatch.emit` needs to validate and route a request.
protocol CarrierStubInputs {
    var carrierType: String { get }
}

/// Carrier validation + 3-way dispatch shared by the seeded algebraic stub
/// emitters (round-trip / idempotence / commutativity / associativity).
///
/// Each emitter's `emit(_:)` was an identical guard-plus-`switch` over
/// `CarrierKind`: validate `inputs.carrierType` against the emitter's
/// `supportedCarriers`, then route `.complexDouble` / `.double` / `.int` to the
/// matching per-carrier composer. That control flow lives here once; the
/// composers stay on each emitter (their bodies are the part that legitimately
/// differs). The emitters keep their public `emit(_:)` as a thin delegation, so
/// the public API is unchanged.
enum CarrierStubDispatch {

    /// Validate `inputs.carrierType` and dispatch to the matching composer.
    /// Throws `VerifyError.unsupportedCarrier` (listing `supportedCarriers`)
    /// when the carrier is outside the `CarrierKind` universe.
    static func emit<Inputs: CarrierStubInputs>(
        _ inputs: Inputs,
        supportedCarriers: [String],
        complexDouble: (Inputs) -> String,
        double: (Inputs) -> String,
        int: (Inputs) -> String
    ) throws -> String {
        guard let carrier = CarrierKind.from(typeName: inputs.carrierType) else {
            throw VerifyError.unsupportedCarrier(
                carrier: inputs.carrierType,
                expected: supportedCarriers
            )
        }
        switch carrier {
        case .complexDouble: return complexDouble(inputs)
        case .double: return double(inputs)
        case .int: return int(inputs)
        }
    }
}
