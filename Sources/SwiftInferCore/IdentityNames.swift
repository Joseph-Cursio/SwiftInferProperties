import Foundation

/// Curated identity-shaped names per PRD v0.3 §5.2 priority 1. Used by
/// `FunctionScannerVisitor.captureIdentityCandidates` (declaration
/// detection) and by `BodySignalVisitor.isIdentityShapedSeed`
/// (member-access seed classification, e.g. `xs.reduce(.empty, op)`).
enum IdentityNames {

    static let curated: Set<String> = [
        "zero",
        "empty",
        "identity",
        "none",
        "default"
    ]
}
