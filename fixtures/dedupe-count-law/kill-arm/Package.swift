// swift-tools-version: 6.0
import PackageDescription

// #671's kill arm (`docs/plans/dedupe-count-law-census-scope.md` §1): SwiftUMLBridge's
// `CoreDataModelExtractor.dedupe(relationships:)`, checked by C1, C2 and the idempotence law the run scored. Run
// by `scripts/dedupe_count_law_kill_arm.py`, which applies the three mutants and records the matrix.
let package = Package(
    name: "DedupeCountLawKillArm",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "4.10.0"),
    ],
    targets: [
        .target(name: "DedupeSubject"),
        .testTarget(
            name: "DedupeLawTests",
            dependencies: [
                "DedupeSubject",
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
            ]
        ),
    ]
)
