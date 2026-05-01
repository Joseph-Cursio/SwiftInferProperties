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
        // SwiftProtocolLaws v1.6.0+ exposes `DerivationStrategist` (and its
        // value types `TypeShape`, `StoredMember`, `RawType`, `MemberSpec`,
        // `DerivationStrategy`) publicly via the `ProtoLawCore` library
        // product. SwiftInferProperties M3 consumes `ProtoLawCore` only —
        // `ProtocolLawKit` transitively pulls swift-testing's
        // `Testing.framework`, which would prevent the `swift-infer`
        // executable from running outside a test context. Local-path until
        // SwiftInferProperties crosses the 1.0 boundary; swap to a
        // versioned URL dep before tagging.
        .package(path: "../SwiftProtocolLaws"),
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
                .product(name: "SwiftParser", package: "swift-syntax"),
                // M3 dep wiring (M3.1) — `ProtoLawCore` exposes
                // `DerivationStrategist` for the M4 generator-inference
                // hookup (PRD §11). M3 itself only references the types
                // (smoke test in SwiftInferCoreTests proves the dep
                // resolves and the public API is callable); active calls
                // into `DerivationStrategist.strategy(for:)` come in M4.
                .product(name: "ProtoLawCore", package: "SwiftProtocolLaws")
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
            dependencies: ["SwiftInferTemplates", "SwiftInferCore"]
        ),
        .testTarget(
            name: "SwiftInferCLITests",
            dependencies: [
                "SwiftInferCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        // SwiftInferIntegrationTests — M1.6 perf integration tests against
        // the §13 budgets, plus M1.7 §16 hard-guarantee tests. Kept in a
        // separate target so the unit suites stay fast while the
        // integration suite has room to scale.
        .testTarget(
            name: "SwiftInferIntegrationTests",
            dependencies: ["SwiftInferTemplates", "SwiftInferCore"]
        )
    ]
)
