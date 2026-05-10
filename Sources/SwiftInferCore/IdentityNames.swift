import Foundation

/// Curated identity-shaped names per PRD v0.3 §5.2 priority 1. Used by
/// `FunctionScannerVisitor.captureIdentityCandidates` (declaration
/// detection), `BodySignalVisitor.isIdentityShapedSeed` (member-access
/// seed classification, e.g. `xs.reduce(.empty, op)`), and v1.19.C's
/// `LiftedIdentityElementPairing` (matches identity-shaped constants
/// against the param-type of `mutating func op(by: X)` lifts).
public enum IdentityNames {

    public static let curated: Set<String> = [
        "zero",
        "empty",
        "identity",
        "none",
        "default"
    ]
}
