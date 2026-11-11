// V1.44.C shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
extension IdempotenceStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.44.C — auto-generated idempotence verify stub.
        // Carrier: \(inputs.carrierType)
        // Function: \(inputs.functionCall) — asserts f(f(x)) ≈ f(x).
        // \(carrierBlurb)
        """
    }
}
