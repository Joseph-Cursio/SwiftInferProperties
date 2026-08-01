// swift-tools-version: 6.1
import PackageDescription

/// **Does the toolchain actually work end to end on real types?**
///
/// The leaderboard fixture measured `discover` alone, which was the wrong question — a
/// perfect PropertyLawKit with nothing left to infer would have scored it 0%. This one
/// wires the kit up and asks the functional question instead: pointed at these types, does
/// the kit run, and does it catch the bug that was planted for it?
///
/// Path dependencies on both siblings, so it runs against whatever is checked out:
///
///     cd fixtures/toolchain-coverage && swift test
///
/// Unlike the other fixtures this one DOES resolve an external package, so it is slower and
/// is not in the sub-second class.
let package = Package(
    name: "ToolchainCoverageFixture",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../leaderboard-sort"),
        .package(path: "../../../SwiftPropertyLaws")
    ],
    targets: [
        .testTarget(
            name: "ToolchainCoverageTests",
            dependencies: [
                .product(name: "LeaderboardSort", package: "leaderboard-sort"),
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws")
            ]
        )
    ]
)
