// swift-tools-version: 6.2
// #674's census over the frozen universe (`docs/plans/encoder-collision-census-scope.md` §1–§4). Not part of the
// package build: run it from this directory with
//   swift run -c release CollisionCensus controls
//   swift run -c release CollisionCensus run ../subjects-<date>.json ../census-<date>.json
import PackageDescription

let package = Package(
    name: "CollisionCensus",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .executableTarget(
            name: "CollisionCensus",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
    ]
)
