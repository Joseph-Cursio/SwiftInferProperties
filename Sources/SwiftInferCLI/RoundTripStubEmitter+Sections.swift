// V1.44.B shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
extension RoundTripStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.44.B — auto-generated round-trip verify stub.
        // Carrier: \(inputs.carrierType)
        // Forward: \(inputs.forwardCall) / Inverse: \(inputs.inverseCall)
        // \(carrierBlurb)
        """
    }
}
