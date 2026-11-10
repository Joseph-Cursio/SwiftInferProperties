import Foundation

// V1.45.A shared section helpers — used by all three per-carrier
// composers. Pure-text composition; no carrier-specific branching.
extension CommutativityStubEmitter {

    static func headerSection(inputs: Inputs, carrierBlurb: String) -> String {
        """
        // V1.45.A — auto-generated commutativity verify stub.
        // Carrier: \(inputs.carrierType)
        // Function: \(inputs.functionCall) — asserts f(a, b) ≈ f(b, a).
        // \(carrierBlurb)
        """
    }
}
