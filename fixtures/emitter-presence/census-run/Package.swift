// swift-tools-version: 6.2
// #673's census over the frozen universe (`docs/plans/emitter-presence-census-scope.md` §2–§4). Not part of the
// package build: run it from this directory with
//   swift run -c release EmitterCensus controls
//   swift run -c release EmitterCensus run ../subjects-<date>.json ../census-<date>.json
import PackageDescription

let package = Package(
    name: "EmitterCensus",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .executableTarget(
            name: "EmitterCensus",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
                .product(name: "SwiftOperators", package: "swift-syntax"),
            ]
        ),
    ]
)
