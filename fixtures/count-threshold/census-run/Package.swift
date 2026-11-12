// swift-tools-version: 6.2
// #670's census over the frozen universe (`docs/plans/count-threshold-boundary-census-scope.md` §2–§4). Not part
// of the package build: run it from this directory with
//   swift run -c release CountThresholdCensus controls
//   swift run -c release CountThresholdCensus run ../subjects-<date>.json ../census-<date>.json
import PackageDescription

let package = Package(
    name: "CountThresholdCensus",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(path: "../../.."),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", exact: "603.0.2"),
    ],
    targets: [
        .executableTarget(
            name: "CountThresholdCensus",
            dependencies: [
                .product(name: "SwiftInferCore", package: "SwiftInferProperties"),
                .product(name: "SwiftInferTemplates", package: "SwiftInferProperties"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax"),
            ]
        ),
    ]
)
