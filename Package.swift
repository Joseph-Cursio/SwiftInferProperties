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
            name: "SwiftInferCore",
            targets: ["SwiftInferCore"]
        ),
        .library(
            name: "SwiftInferTemplates",
            targets: ["SwiftInferTemplates"]
        ),
        .library(
            name: "SwiftInferCLI",
            targets: ["SwiftInferCLI"]
        ),
        .executable(
            name: "swift-infer",
            targets: ["swift-infer"]
        )
    ],
    dependencies: [
        // SwiftProtocolLaws dep re-enabled at M3 once `DerivationStrategist`
        // (currently `package`-visible in `ProtoLawCore`) is promoted to
        // `public` per PRD §11 / §21 OQ #4. The dep will target `ProtoLawCore`,
        // not `ProtocolLawKit` — ProtocolLawKit transitively pulls
        // swift-testing's `Testing.framework`, which would prevent the
        // `swift-infer` executable from running outside a test context.
        // .package(path: "../SwiftProtocolLaws"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        // SwiftInferCore — shared data model (FunctionSummary, Suggestion,
        // Score, ExplainabilityBlock). Pure data + parsing utilities; no CLI.
        .target(
            name: "SwiftInferCore",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        // SwiftInferTemplates — TemplateEngine template registry. M1 ships
        // round-trip and idempotence; subsequent milestones add the rest.
        .target(
            name: "SwiftInferTemplates",
            dependencies: ["SwiftInferCore"]
        ),
        // SwiftInferCLI — ArgumentParser-driven command surface. Subcommands
        // (discover, drift, etc.) live here; the executable target is a thin
        // entry point.
        .target(
            name: "SwiftInferCLI",
            dependencies: [
                "SwiftInferCore",
                "SwiftInferTemplates",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // swift-infer — executable. Sources/swift-infer/main.swift only
        // forwards to SwiftInferCommand.main(); no logic lives here.
        .executableTarget(
            name: "swift-infer",
            dependencies: ["SwiftInferCLI"]
        ),
        .testTarget(
            name: "SwiftInferCoreTests",
            dependencies: ["SwiftInferCore"]
        ),
        .testTarget(
            name: "SwiftInferTemplatesTests",
            dependencies: ["SwiftInferTemplates"]
        ),
        .testTarget(
            name: "SwiftInferCLITests",
            dependencies: [
                "SwiftInferCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
