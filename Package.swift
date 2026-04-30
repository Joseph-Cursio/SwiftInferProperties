// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SwiftInferProperties",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftInfer",
            targets: ["SwiftInfer"]
        )
    ],
    dependencies: [
        // SwiftProtocolLaws is wired in via local path during M1–M9 development
        // so SwiftInfer can iterate against unreleased ProtocolLawKit / shared
        // DerivationStrategist changes (PRD §4.5, §5.7). Swap to a versioned
        // URL dep before tagging SwiftInferProperties 1.0.
        .package(path: "../SwiftProtocolLaws"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .target(
            name: "SwiftInfer",
            dependencies: [
                .product(name: "ProtocolLawKit", package: "SwiftProtocolLaws"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "SwiftInferTests",
            dependencies: ["SwiftInfer"]
        )
    ]
)
