// swift-tools-version: 6.1
import PackageDescription

/// Fixture for the **verify-refutability experiment**: which law shapes can a derived
/// generator actually refute?
///
/// **Every function in this package is deliberately WRONG.** That is the whole design: if
/// every stub violates the law `discover` proposes for it, then any `measured-bothPass` is a
/// **false negative of the verifier** — a law shape verification cannot police. No judgement
/// call is needed to read the result.
///
/// Deliberately dependency-free. The verifier builds its own workdir with its own
/// PropertyLawKit pin (`VerifierWorkdir.swiftPropertyLawsRequirement`), so this package must
/// not carry a pin of its own to drift from it — the failure mode CLAUDE.md records, where
/// disjoint major ranges make every entry report `measured-error: build-failed` and read as an
/// architectural limitation rather than a broken manifest.
let package = Package(
    name: "VerifyRefutability",
    platforms: [.macOS(.v14)],
    targets: [.target(name: "VerifyRefutability")]
)
