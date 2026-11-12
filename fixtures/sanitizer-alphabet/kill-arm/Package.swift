// swift-tools-version: 6.0
import PackageDescription

// #672's kill arm (`docs/plans/sanitizer-alphabet-census-scope.md` §1): SwiftUMLBridge's
// `ERScript.sanitizeType(_:)`, checked by idempotence, law 1 (fixed point) and law 2 (output alphabet). Run by
// `scripts/sanitizer_alphabet_kill_arm.py`, which applies the five mutants and records the matrix.
let package = Package(
    name: "SanitizerAlphabetKillArm",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "4.10.0"),
    ],
    targets: [
        .target(name: "SanitizerSubject"),
        .testTarget(
            name: "SanitizerLawTests",
            dependencies: [
                "SanitizerSubject",
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
            ]
        ),
    ]
)
