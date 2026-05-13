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

        public init(
            workdir: URL,
            userPackage: UserPackageReference?,
            stubSource: String
        ) {
            self.workdir = workdir
            self.userPackage = userPackage
            self.stubSource = stubSource
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
        let mainPath = sourcesDir.appendingPathComponent("main.swift")
        let packageSource = renderPackageSwift(userPackage: inputs.userPackage)
        try packageSource.write(to: packagePath, atomically: true, encoding: .utf8)
        try inputs.stubSource.write(to: mainPath, atomically: true, encoding: .utf8)
        return mainPath
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
    static func renderPackageSwift(userPackage: UserPackageReference?) -> String {
        let dependenciesBlock = renderDependenciesBlock(userPackage: userPackage)
        let targetDependenciesBlock = renderTargetDependenciesBlock(userPackage: userPackage)
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

    /// Build the comma-joined `dependencies:` array. The numerics +
    /// property-based packages are mandatory; the user package is
    /// optional. Comma placement follows SwiftPM's accepted style —
    /// trailing comma after the last entry is legal but we omit it
    /// here for tidiness.
    private static func renderDependenciesBlock(userPackage: UserPackageReference?) -> String {
        var entries = [
            ".package(url: \"https://github.com/apple/swift-numerics.git\", from: \"1.0.0\")",
            // V1.59.A — swift-collections for OrderedSet / OrderedDictionary
            // carriers. Required for the curated OC recipes in
            // `StrategistDispatchEmitter.curatedOCRecipe`. v1.58 added the
            // bare→qualified binding `OrderedSet → OrderedSet<Int>`; v1.59
            // wires the dependency so the synthesized workdir can import
            // `OrderedCollections`.
            ".package(url: \"https://github.com/apple/swift-collections.git\", from: \"1.0.0\")",
            ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
            ".package(url: \"https://github.com/Joseph-Cursio/SwiftPropertyLaws.git\", from: \"2.1.0\")"
        ]
        if let userPackage {
            entries.append(".package(path: \(escapedLiteral(userPackage.packagePath.path)))")
        }
        return entries
            .map { "        \($0)" }
            .joined(separator: ",\n")
    }

    /// Build the comma-joined target `dependencies:` array. Four kit
    /// deps (`ComplexModule`, `RealModule`, `PropertyBased`,
    /// `PropertyLawComplex`) are always present from V1.43.A; user
    /// products append when supplied. `PropertyLawComplex` is the
    /// opt-in library product introduced at `SwiftPropertyLaws v2.1.0`
    /// that exposes `Gen<Complex<Double>>.edgeCaseBiased()` for the
    /// V1.43.B two-pass design.
    private static func renderTargetDependenciesBlock(userPackage: UserPackageReference?) -> String {
        var entries = [
            ".product(name: \"ComplexModule\", package: \"swift-numerics\")",
            // V1.59.A — OrderedCollections product for OC carriers.
            ".product(name: \"OrderedCollections\", package: \"swift-collections\")",
            ".product(name: \"RealModule\", package: \"swift-numerics\")",
            ".product(name: \"PropertyBased\", package: \"swift-property-based\")",
            ".product(name: \"PropertyLawComplex\", package: \"SwiftPropertyLaws\")"
        ]
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
