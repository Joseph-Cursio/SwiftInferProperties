// swift-tools-version: 6.1
import CompilerPluginSupport
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
        // TestLifter M1.0: PRD §7 Contribution 2 — analyzes existing
        // XCTest + Swift Testing suites, slices test bodies into setup +
        // property regions (PRD §7.2), and emits LiftedSuggestions whose
        // identities feed TemplateEngine's `crossValidationFromTestLifter`
        // parameter for the +20 PRD §4.1 cross-validation signal. M1
        // ships parser + slicer + assert-after-transform → round-trip
        // detection only; M2+ add idempotence / commutativity / etc.
        .library(
            name: "SwiftInferTestLifter",
            targets: ["SwiftInferTestLifter"]
        ),
        .library(
            name: "SwiftInferCLI",
            targets: ["SwiftInferCLI"]
        ),
        // M5.2: user-facing macro library. Users import this in their
        // test target and write `@CheckProperty(.idempotent)` on the
        // function under test. The macro's expanded test stub references
        // `ProtocolLawKit.SwiftPropertyBasedBackend` and `Seed`, so the
        // library re-exports `ProtocolLawKit` to spare users a second
        // import. Test targets DO want `Testing.framework` (which the
        // kit transitively pulls), so the v0.4 §16 #6 Testing-framework
        // exclusion that holds for the `swift-infer` executable doesn't
        // bite here.
        .library(
            name: "SwiftInferMacro",
            targets: ["SwiftInferMacro"]
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
        // product. SwiftInferProperties M3 consumes `ProtoLawCore`;
        // M7.4's RefactorBridge writeouts emit `extension TypeName:
        // Semigroup {}` / `Monoid {}` against `import ProtocolLawKit`,
        // requiring v1.8.0+ (the kit's first kit-defined protocol cluster).
        // M8's RefactorBridge widens this surface to `extension TypeName:
        // CommutativeMonoid {}` / `Group {}` / `Semilattice {}`, requiring
        // **v1.9.0+** (the kit's second algebraic cluster — M8.0 prereq
        // shipped at SwiftProtocolLaws tag `v1.9.0`, 2026-05-02).
        // `ProtocolLawKit` transitively pulls swift-testing's
        // `Testing.framework`, which would prevent the `swift-infer`
        // executable from running outside a test context — only the
        // generated test-target writeouts import it.
        .package(url: "https://github.com/Joseph-Cursio/SwiftProtocolLaws.git", from: "1.9.0"),
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
        // M4.2 adds the `ProtoLawCore` dep so `GeneratorSelection` can
        // call `DerivationStrategist.strategy(for:)` directly — Core
        // already pulls the same product (M3.1), but SwiftPM doesn't
        // re-export transitively, so the import has to be explicit here.
        .target(
            name: "SwiftInferTemplates",
            dependencies: [
                "SwiftInferCore",
                .product(name: "ProtoLawCore", package: "SwiftProtocolLaws")
            ]
        ),
        // SwiftInferTestLifter — TestLifter M1.0. Mirror of SwiftInferTemplates'
        // dep shape (Core + swift-syntax). Stays out of SwiftInferCLI's deps
        // until M1.5 wires the discover subcommand to scan tests too.
        .target(
            name: "SwiftInferTestLifter",
            dependencies: [
                "SwiftInferCore",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
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
        // M5.2: user-facing macro target — declarations only. Re-exports
        // `ProtocolLawKit` so users importing `SwiftInferMacro` can use
        // the macro-emitted `SwiftPropertyBasedBackend` + `Seed` types
        // without a second import. The actual macro impl lives in
        // `SwiftInferMacroImpl` below; this target exposes the
        // `@CheckProperty` attribute attached to it.
        .target(
            name: "SwiftInferMacro",
            dependencies: [
                "SwiftInferMacroImpl",
                .product(name: "ProtocolLawKit", package: "SwiftProtocolLaws")
            ]
        ),
        // M5.2: compiler-plugin target hosting the macro implementation.
        // Plugin targets compile against swift-syntax and run during
        // macro expansion (a separate compiler subprocess). Mirrors the
        // kit's `ProtoLawMacroImpl` shape. Depends on `SwiftInferCore`
        // for the `SamplingSeed` derivation that the expansion embeds
        // as a literal `Seed(stateA:stateB:stateC:stateD:)` in the
        // emitted test stub, and on `ProtoLawCore` for the
        // `GeneratorExpressionEmitter` (K-prep-M1) that turns a
        // `DerivationStrategy` into the generator expression text the
        // emitted test will reference.
        .macro(
            name: "SwiftInferMacroImpl",
            dependencies: [
                "SwiftInferCore",
                // M6.3: SwiftInferTemplates dep for the shared
                // `LiftedTestEmitter` — the macro impl now delegates
                // its idempotent / round-trip text emission to the
                // emitter so the macro path and M6.4's interactive-
                // accept writeout share one canonical stub shape.
                "SwiftInferTemplates",
                .product(name: "ProtoLawCore", package: "SwiftProtocolLaws"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
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
        // TestLifter M1.0 — smoke test target. M1.1+ fill out the suites
        // for parser, slicer, detector, identity-equality. M1.4 adds
        // the SwiftInferTemplates dep so the load-bearing
        // CrossValidationKey-parity test can build a TemplateRegistry
        // suggestion alongside a LiftedSuggestion and assert key
        // equality.
        .testTarget(
            name: "SwiftInferTestLifterTests",
            dependencies: ["SwiftInferTestLifter", "SwiftInferTemplates", "SwiftInferCore"]
        ),
        .testTarget(
            name: "SwiftInferCLITests",
            dependencies: [
                "SwiftInferCLI",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "SwiftInferMacroTests",
            dependencies: [
                "SwiftInferMacro",
                "SwiftInferMacroImpl",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),
        // SwiftInferIntegrationTests — M1.6 perf integration tests against
        // the §13 budgets, plus M1.7 §16 hard-guarantee tests. Kept in a
        // separate target so the unit suites stay fast while the
        // integration suite has room to scale. SwiftInferCLI dep added in
        // M6.2 so the discover→snapshot→reload integration test can call
        // BaselineLoader without re-implementing its read+write path.
        .testTarget(
            name: "SwiftInferIntegrationTests",
            dependencies: ["SwiftInferTemplates", "SwiftInferCore", "SwiftInferCLI"]
        )
    ]
)
