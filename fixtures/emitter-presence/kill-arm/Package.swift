// swift-tools-version: 6.0
import PackageDescription

// #673's kill arm (`docs/plans/emitter-presence-census-scope.md` §1): SwiftUMLBridge's
// `ComponentScript.buildPlantUMLText` and `buildMermaidText`, checked by determinism, bare presence and template
// presence under two generators. Run by `scripts/emitter_presence_kill_arm.py`, which applies the nine recorded
// `RemoveSideEffects` mutants and records the matrix.
let package = Package(
    name: "EmitterPresenceKillArm",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "4.10.0"),
    ],
    targets: [
        .target(name: "EmitterSubject"),
        .testTarget(
            name: "EmitterLawTests",
            dependencies: [
                "EmitterSubject",
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
            ]
        ),
    ]
)
