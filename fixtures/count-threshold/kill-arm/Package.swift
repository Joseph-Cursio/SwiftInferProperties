// swift-tools-version: 6.0
import PackageDescription

// #670's kill arm (`docs/plans/count-threshold-boundary-census-scope.md` §1): `compactText` at two
// SwiftUMLStudio revisions, checked by Law 1, Law 2 and the idempotence law the tool emits. Run by
// `scripts/count_threshold_kill_arm.py`, which mutates the threshold line and records the matrix.
let package = Package(
    name: "CountThresholdKillArm",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "4.10.0"),
    ],
    targets: [
        .target(name: "CompactTextSubject"),
        .testTarget(
            name: "CompactTextLawTests",
            dependencies: [
                "CompactTextSubject",
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
            ]
        ),
    ]
)
