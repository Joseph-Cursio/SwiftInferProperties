import Foundation

/// V1.42.C.3 — synthesizes the throwaway SwiftPM verifier package + spawns
/// `swift build` and the resulting binary. Two cooperating types:
///
///   - `VerifierWorkdir` — pure-ish workdir synthesis. Given a destination
///     directory, the user's package path, the C.2-emitted stub source,
///     and the extra-imports list, writes `Package.swift` +
///     `Sources/SwiftInferVerifier/main.swift`. Idempotent on `.build/`
///     so repeated calls benefit from SwiftPM's incremental cache.
///
///   - `VerifierSubprocess` — wraps `Process` invocations of `swift build`
///     and the verifier binary. Returns the raw exit code + stdout/stderr
///     so V1.42.C.4 can parse the `VERIFY_*` markers and render the
///     user-facing outcome.
///
/// **Workdir location.** `<packageRoot>/.swiftinfer/verify-workdir/<hashPrefix>/`.
/// One directory per suggestion-hash-prefix so concurrent verify calls
/// against different suggestions don't stomp on each other's `.build/`
/// directory. The hash prefix is filename-safe (hex digits only after
/// `0x` stripping).
///
/// **Always-rebuild scope.** V1.42.C.3 doesn't cache results — each
/// verify call re-runs `swift build` (incremental within SwiftPM's
/// cache but full from the harness's perspective) and re-runs the
/// binary. Phase 3 of the v1.42 plan layers a SQLite-backed cache;
/// not yet wired.
public enum VerifierWorkdir {

    /// User package + target reference for the verifier's dependency
    /// graph. Optional — verifying ComplexModule's own surface
    /// (`Complex.exp` etc.) doesn't require a user-package dep.
    ///
    /// **Limitation in v1.42.** User targets must be exposed as a
    /// library product in the user's `Package.swift` for the
    /// `.product(name:package:)` declaration to resolve. Targets only
    /// declared (without a matching product) can't be verified in
    /// v1.42 — the build step fails and surfaces via the eventual
    /// V1.42.C.3 `.buildFailed` error. `packageDeclaredName` is the
    /// `name:` value the user passed to `Package(name: ..., ...)`,
    /// which SwiftPM uses as the `package:` argument in
    /// `.product(name:package:)` resolutions. Most user packages
    /// declare a name that matches the directory basename; when it
    /// doesn't, the caller must supply the actual declared name.
    public struct UserPackageReference: Equatable, Sendable {
        public let packagePath: URL
        public let packageDeclaredName: String
        public let productNames: [String]

        public init(packagePath: URL, packageDeclaredName: String, productNames: [String]) {
            self.packagePath = packagePath
            self.packageDeclaredName = packageDeclaredName
            self.productNames = productNames
        }
    }

    /// Inputs to synthesizing the workdir. Wrapped in a struct so the
    /// emitter signature stays under the `function_parameter_count`
    /// lint cap and the call site at the eventual harness glue (C.6)
    /// reads naturally.
    public struct Inputs: Equatable, Sendable {
        /// Where to write the workdir. Typically
        /// `<packageRoot>/.swiftinfer/verify-workdir/<hashPrefix>/`.
        public let workdir: URL

        /// User-package dep + library products to depend on. `nil`
        /// when verifying ComplexModule's own surface — the workdir's
        /// Package.swift then declares only the swift-numerics +
        /// swift-property-based deps.
        public let userPackage: UserPackageReference?

        /// Already-emitted main.swift source per V1.42.C.2.
        public let stubSource: String

        /// V2.0 M3.E.2 — which dep shape to render. `.algebraic`
        /// (the default, preserving v1.42 callers' behavior) declares
        /// swift-numerics + swift-collections + swift-property-based
        /// + SwiftPropertyLaws@2.1.0 + PropertyLawComplex.
        /// `.interaction` declares swift-property-based +
        /// SwiftPropertyLaws@2.2.0 + PropertyLawKit (no numerics /
        /// collections / PropertyLawComplex — the interaction-verify
        /// stub doesn't import them).
        public let mode: WorkdirMode

        /// Cycle 122 (Phase A) — corpus sources to compile **into** the
        /// verifier target (direct source inclusion), used by the
        /// `.interactionTCA` path so a real `internal` TCA reducer is
        /// visible without `import`/`@testable`. Empty (the default) keeps
        /// the v1.42 path-dependency model: the stub is `main.swift` and
        /// the user package is referenced via `userPackage`. Non-empty:
        /// the stub is `Verifier.swift` (avoids the `@main` + `main.swift`
        /// top-level-code conflict) and each file is written alongside it.
        public let inlinedSources: [CorpusPackager.SourceFile]

        public init(
            workdir: URL,
            userPackage: UserPackageReference?,
            stubSource: String,
            mode: WorkdirMode = .algebraic,
            inlinedSources: [CorpusPackager.SourceFile] = []
        ) {
            self.workdir = workdir
            self.userPackage = userPackage
            self.stubSource = stubSource
            self.mode = mode
            self.inlinedSources = inlinedSources
        }
    }

    /// Synthesize the workdir on disk. Creates:
    ///
    ///   - `<workdir>/Package.swift`
    ///   - `<workdir>/Sources/SwiftInferVerifier/main.swift`
    ///
    /// Returns the path to the synthesized `main.swift` so V1.42.D
    /// integration tests can read it back. The `.build/` directory
    /// (if present from a previous run) is untouched.
    public static func synthesize(_ inputs: Inputs) throws -> URL {
        let sourcesDir = inputs.workdir
            .appendingPathComponent("Sources")
            .appendingPathComponent("SwiftInferVerifier")
        try FileManager.default.createDirectory(
            at: sourcesDir,
            withIntermediateDirectories: true
        )
        let packagePath = inputs.workdir.appendingPathComponent("Package.swift")
        // Cycle 122 — with co-compiled corpus sources, the stub can't be
        // `main.swift` (the `@main` + top-level-code conflict); name it
        // `Verifier.swift`. Without inlined sources, keep the v1.42
        // `main.swift` shape.
        let stubFileName = inputs.inlinedSources.isEmpty ? "main.swift" : "Verifier.swift"
        let stubPath = sourcesDir.appendingPathComponent(stubFileName)
        let packageSource = renderPackageSwift(
            userPackage: inputs.userPackage,
            mode: inputs.mode
        )
        try writeIfChanged(packageSource, to: packagePath)
        try writeIfChanged(inputs.stubSource, to: stubPath)
        // Direct source inclusion — write each corpus file into the same
        // target so `internal` reducer/State/Action types are in-module.
        for source in inputs.inlinedSources {
            try writeIfChanged(
                source.contents,
                to: sourcesDir.appendingPathComponent(source.name)
            )
        }
        return stubPath
    }

    /// Cycle 129 — write `content` to `url` only if the file is absent or
    /// its contents differ. Skipping an unchanged write preserves the
    /// file's mtime, so SwiftPM/llbuild sees no change and the build stays
    /// incremental — the basis for the shared-warm-workdir survey (an
    /// identical co-compiled corpus + deps recompile once; only the
    /// per-identity stub triggers a rebuild). Atomic when it does write.
    private static func writeIfChanged(_ content: String, to url: URL) throws {
        if let existing = try? String(contentsOf: url, encoding: .utf8), existing == content {
            return
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Package.swift rendering

    /// Emit the verifier package's `Package.swift`. swift-numerics and
    /// swift-property-based pin to the same minor lines as the kit's
    /// own `SwiftPropertyLaws` v2.1.0 deps so the verifier's resolved
    /// graph matches what the kit would build.
    ///
    /// **V1.43.A** — the workdir now additionally depends on
    /// `SwiftPropertyLaws` for the `PropertyLawComplex` library
    /// product. Pinned `from: "2.1.0"` to match the user-side
    /// `Package.swift` (V1.42.A). `PropertyLawComplex` ships
    /// `Gen<Complex<Double>>.edgeCaseBiased()` + the curated 12-entry
    /// `complexEdgeCases` set, which V1.43.B consumes for the two-pass
    /// design. The dep is additive; existing `swift-numerics` and
    /// `swift-property-based` lines are untouched.
    static func renderPackageSwift(
        userPackage: UserPackageReference?,
        mode: WorkdirMode = .algebraic
    ) -> String {
        let dependenciesBlock = renderDependenciesBlock(userPackage: userPackage, mode: mode)
        let targetDependenciesBlock = renderTargetDependenciesBlock(
            userPackage: userPackage,
            mode: mode
        )
        return """
        // swift-tools-version: 6.1
        // V1.42.C.3 auto-generated. Do not edit.
        import PackageDescription

        let package = Package(
            name: "SwiftInferVerifier",
            platforms: [
                .macOS(.v14)
            ],
            dependencies: [
        \(dependenciesBlock)
            ],
            targets: [
                .executableTarget(
                    name: "SwiftInferVerifier",
                    dependencies: [
        \(targetDependenciesBlock)
                    ]
                )
            ]
        )
        """
    }

    /// Build the comma-joined `dependencies:` array. Mode-dependent:
    /// `.algebraic` (v1.42 default) declares swift-numerics +
    /// swift-collections + swift-property-based + SwiftPropertyLaws@2.1.0.
    /// `.interaction` (V2.0 M3.E.2) declares swift-property-based +
    /// SwiftPropertyLaws@2.2.0 only — numerics / collections aren't
    /// imported by M3.B's emitted stub. Comma placement follows
    /// SwiftPM's accepted style — trailing comma after the last entry
    /// is legal but we omit it here for tidiness.
    private static func renderDependenciesBlock(
        userPackage: UserPackageReference?,
        mode: WorkdirMode
    ) -> String {
        var entries: [String]
        switch mode {
        case .algebraic:
            entries = [
                ".package(url: \"https://github.com/apple/swift-numerics.git\", from: \"1.0.0\")",
                // V1.59.A — swift-collections for OrderedSet /
                // OrderedDictionary carriers. Required for the curated
                // OC recipes in `StrategistDispatchEmitter.curatedOCRecipe`.
                ".package(url: \"https://github.com/apple/swift-collections.git\", from: \"1.0.0\")",
                ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
                ".package(url: \"https://github.com/Joseph-Cursio/SwiftPropertyLaws.git\", from: \"2.1.0\")"
            ]

        case .interaction:
            // V2.0 M3.E.2 — interaction verify needs the v2.2.0 kit
            // surface (ActionSequenceFactory + StatefulGuard, shipped
            // alongside PropertyLawKit). swift-property-based is a
            // transitive dep — declared explicitly so the synthesized
            // workdir's Package.swift resolves without leaning on
            // the kit's own dep graph.
            entries = [
                ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
                ".package(url: \"https://github.com/Joseph-Cursio/SwiftPropertyLaws.git\", from: \"2.2.0\")"
            ]

        case .interactionTCA:
            // Cycle 122 — interaction deps + TCA. The corpus is compiled
            // into the verifier target (direct source inclusion), so there
            // is no user-package path dependency — just CA for the macros
            // and runtime the co-compiled reducer needs.
            entries = [
                ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
                ".package(url: \"https://github.com/Joseph-Cursio/SwiftPropertyLaws.git\", from: \"2.2.0\")",
                ".package(url: "
                    + "\"https://github.com/pointfreeco/swift-composable-architecture.git\", "
                    + "from: \"1.15.0\")"
            ]
        }
        if let userPackage {
            entries.append(".package(path: \(escapedLiteral(userPackage.packagePath.path)))")
        }
        return entries
            .map { "        \($0)" }
            .joined(separator: ",\n")
    }

    /// Build the comma-joined target `dependencies:` array.
    /// Mode-dependent: `.algebraic` (v1.42 default) declares
    /// ComplexModule + OrderedCollections + RealModule + PropertyBased
    /// + PropertyLawComplex. `.interaction` (V2.0 M3.E.2) declares
    /// PropertyBased + PropertyLawKit only — the M3.B-emitted stub
    /// imports just those. User products append in either mode.
    private static func renderTargetDependenciesBlock(
        userPackage: UserPackageReference?,
        mode: WorkdirMode
    ) -> String {
        var entries: [String]
        switch mode {
        case .algebraic:
            entries = [
                ".product(name: \"ComplexModule\", package: \"swift-numerics\")",
                ".product(name: \"OrderedCollections\", package: \"swift-collections\")",
                ".product(name: \"RealModule\", package: \"swift-numerics\")",
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawComplex\", package: \"SwiftPropertyLaws\")"
            ]

        case .interaction:
            entries = [
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")"
            ]

        case .interactionTCA:
            entries = [
                ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
                ".product(name: \"PropertyLawKit\", package: \"SwiftPropertyLaws\")",
                ".product(name: \"ComposableArchitecture\", "
                    + "package: \"swift-composable-architecture\")"
            ]
        }
        if let userPackage {
            for productName in userPackage.productNames {
                entries.append(
                    ".product(name: \(escapedLiteral(productName)), "
                        + "package: \(escapedLiteral(userPackage.packageDeclaredName)))"
                )
            }
        }
        return entries
            .map { "                \($0)" }
            .joined(separator: ",\n")
    }

    /// Escape a string for safe inclusion as a Swift string literal
    /// in the rendered Package.swift. Handles backslashes + double
    /// quotes (the typical filename-path concerns); doesn't
    /// special-case newlines because workdir paths shouldn't
    /// contain them.
    static func escapedLiteral(_ raw: String) -> String {
        let escaped = raw
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

/// V2.0 M3.E.2 — selects which dependency shape `VerifierWorkdir`
/// renders into the synthesized package's `Package.swift`. Hoisted to
/// file scope so it doesn't increase nesting depth past SwiftLint's
/// 1-level cap on `VerifierWorkdir` (already nested inside the
/// `SwiftInferCommand` extension hierarchy).
///
/// - `algebraic`: the v1.42+ shape — swift-numerics + swift-collections
///   + swift-property-based + SwiftPropertyLaws@2.1.0 + PropertyLawComplex.
///   Used by `verify` for round-trip / idempotence / commutativity /
///   associativity / dual-style / monotonicity templates.
/// - `interaction`: the V2.0 M3 shape — swift-property-based +
///   SwiftPropertyLaws@2.2.0 + PropertyLawKit. Used by
///   `verify-interaction` for the action-sequence stub M3.B emits.
public enum WorkdirMode: String, Sendable, Equatable, Codable, CaseIterable {
    case algebraic
    case interaction
    /// Cycle 122 (Phase A) — the interaction shape plus
    /// swift-composable-architecture (so the co-compiled corpus reducer +
    /// the stub's `import ComposableArchitecture` resolve). Paired with
    /// `Inputs.inlinedSources` (direct source inclusion); no user-package
    /// path dependency.
    case interactionTCA = "interaction-tca"
}
