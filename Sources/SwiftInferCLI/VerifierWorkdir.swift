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
/// **That rationale no longer covers the survey**, and reading it as though it does
/// costs 15×. It is a statement about two *concurrent* runs sharing a `.build/` — it
/// was never an argument that 53 sequential entries each need their own dependency
/// graph, which is what it was taken to license. `verify --all-from-index` now builds
/// one package with one executable target per suggestion (`SharedVerifierPackage`);
/// this type still serves the single-suggestion path, where the hash-keyed root is
/// exactly right and the isolation above still applies.
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
    /// V1.42.C.3 `.buildFailed` error.
    ///
    /// **Package identity.** For a `.package(path:)` dependency, SwiftPM
    /// (tools 5.6+) derives the package *identity* from the dependency
    /// directory's **basename** — NOT the `name:` value in the user's
    /// `Package(name: ..., ...)`. That identity is what the
    /// `.product(name:package:)` `package:` argument must reference, so
    /// it's computed here from `packagePath` (`packageIdentity`) rather
    /// than taken as a caller input. Passing the module/product name as
    /// the `package:` argument — as an earlier revision did — build-fails
    /// with "unknown package" whenever the repo directory name differs
    /// from the module name (the common case for real user packages; the
    /// measured-test corpora dodged it because `CorpusPackager` names the
    /// corpus directory after the module). `productNames` remains the
    /// library product name(s) to depend on, which SwiftPM matches
    /// case-insensitively.
    public struct UserPackageReference: Equatable, Sendable {
        public let packagePath: URL
        public let productNames: [String]

        public init(packagePath: URL, productNames: [String]) {
            self.packagePath = packagePath
            self.productNames = productNames
        }

        /// The SwiftPM package identity for the `.package(path:)`
        /// dependency — the path basename. Used as the `package:`
        /// argument in `.product(name:package:)`.
        var packageIdentity: String {
            packagePath.lastPathComponent
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
                \(macOSPlatformLine(userPackage: userPackage))
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

    /// The verifier package's macOS deployment target, mirrored from the corpus.
    ///
    /// **A hardcoded floor cannot work here, and the failure is total rather than
    /// partial.** SwiftPM refuses to link an executable requiring an older
    /// platform than a product it depends on, so a verifier pinned to
    /// `.macOS(.v14)` against a corpus declaring `.macOS(.v26)` fails *every*
    /// entry with `requires macos 14.0, but depends on the product '<Module>'
    /// which requires macos 26.0` — reported as `build-failed`, i.e. as a
    /// tooling error rather than as the version mismatch it is. Measured on
    /// SwiftProjectLint (2026-08-05): 60 of 60 picks, before this existed.
    ///
    /// Raising the constant just moves the wall: pinning 26 breaks every corpus
    /// that deploys lower, which is most of them. The requirement is not a
    /// number, it is *agreement with the corpus*, so it is read from the corpus.
    ///
    /// Deliberately a text scan, not a manifest evaluation. Evaluating a
    /// `Package.swift` means running it, which is a `swift package dump-package`
    /// subprocess per workdir for one integer. The regex covers both spellings
    /// (`.macOS(.v26)` and `.macOS("26.0")`) and takes the highest it finds;
    /// anything it cannot read falls back to `defaultMacOSVersion`, which is the
    /// behaviour every corpus had before. A missed declaration therefore
    /// degrades to the old failure rather than to a new one.
    ///
    /// Emitted in the **string** form (`.macOS("26.0")`) rather than
    /// `.macOS(.v26)`: the generated manifest is `swift-tools-version: 6.1`, and
    /// `.v26` does not exist in that version's `PackageDescription` — it fails
    /// with `'v26' is unavailable`. The string form is accepted at every tools
    /// version and needs no table of enum cases to stay current.
    static func macOSPlatformLine(userPackage: UserPackageReference?) -> String {
        let version = userPackage
            .flatMap { declaredMacOSVersion(inPackageAt: $0.packagePath) }
            ?? defaultMacOSVersion
        return ".macOS(\"\(version)\")"
    }

    /// The floor used when the corpus declares nothing readable — unchanged from
    /// the constant this replaced, so a corpus that worked before still does.
    static let defaultMacOSVersion = "14.0"

    /// Highest macOS version declared in `<packagePath>/Package.swift`, or `nil`.
    static func declaredMacOSVersion(inPackageAt packagePath: URL) -> String? {
        guard let manifest = try? String(
            contentsOf: packagePath.appendingPathComponent("Package.swift"), encoding: .utf8
        ) else {
            return nil
        }
        // `.macOS(.v26)` → "26.0"; `.macOS("26.0")` / `.macOS("26")` → as written.
        // Compared numerically by major version: string ordering would rank
        // "9.0" above "14.0", which is the whole reason this is not a `max()`
        // over the raw matches.
        let patterns = [#"\.macOS\(\.v([0-9]+)\)"#, #"\.macOS\("([0-9]+)(?:\.[0-9]+)*"\)"#]
        var best: Int?
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(manifest.startIndex..., in: manifest)
            for match in regex.matches(in: manifest, range: range) {
                guard let majorRange = Range(match.range(at: 1), in: manifest),
                      let major = Int(manifest[majorRange]) else {
                    continue
                }
                best = Swift.max(best ?? major, major)
            }
        }
        return best.map { "\($0).0" }
    }

    /// Whether the corpus at `packagePath` declares a swift-syntax dependency.
    ///
    /// Gates both the `.package(…)` line and the `.product(…)` entries for the
    /// SwiftSyntax carrier recipes — see the call site in
    /// `renderDependenciesBlock` for why this condition is exactly equivalent to
    /// "those recipes can be reached".
    ///
    /// Matches the repository URL rather than a product name: the package can be
    /// spelled `swiftlang/swift-syntax` or the older `apple/swift-syntax`, and a
    /// corpus may re-export it under any target name. A corpus that reaches
    /// swift-syntax only transitively (through a dependency that links it, never
    /// naming it itself) reads as `false` here — correctly, since a function
    /// whose *signature* names a syntax node needs the direct dependency to
    /// compile at all.
    static func packageDependsOnSwiftSyntax(at packagePath: URL) -> Bool {
        guard let manifest = try? String(
            contentsOf: packagePath.appendingPathComponent("Package.swift"), encoding: .utf8
        ) else {
            return false
        }
        return manifest.contains("swift-syntax")
    }

    /// Build the comma-joined `dependencies:` array. Mode-dependent:
    /// `.algebraic` (v1.42 default) declares swift-numerics +
    /// swift-collections + swift-property-based + SwiftPropertyLaws.
    /// `.interaction` (V2.0 M3.E.2) declares swift-property-based +
    /// SwiftPropertyLaws only — numerics / collections aren't
    /// imported by M3.B's emitted stub. Every mode takes its kit
    /// requirement from `swiftPropertyLawsRequirement`; see that constant
    /// for why it may not be spelled out per-mode. Comma placement follows
    /// SwiftPM's accepted style — trailing comma after the last entry
    /// is legal but we omit it here for tidiness.
    /// Internal rather than private: `SharedVerifierPackage` renders the same
    /// package-level dependency list for the survey package. Two spellings of
    /// "what does an algebraic stub need" would drift.
    static func renderDependenciesBlock(
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
                swiftPropertyLawsDependencyLine
            ]
            // swift-syntax, **only when the corpus already depends on it**.
            //
            // Declaring it unconditionally is what the first draft did, and it
            // is measurably wrong: `swift test` on this repo went from
            // `peakDeltaMB=233.7` to `8871.4` against a 800 MB §13 budget,
            // because every verify integration test in the suite began
            // resolving and building a large module it had no use for.
            //
            // The gate is not a heuristic. A corpus function can only *take* a
            // `FunctionCallExprSyntax` if the corpus itself links swift-syntax,
            // so "the syntax recipes are reachable" and "the corpus declares
            // swift-syntax" are the same condition. Where the recipes are
            // needed, the module is already in the graph and this line adds no
            // build; where they are not, it adds nothing at all.
            if let userPackage, packageDependsOnSwiftSyntax(at: userPackage.packagePath) {
                // Range, not `from:`. swift-syntax versions its releases by
                // Swift release (600 / 601 / 602), so `from: "600.0.0"` means
                // `600.0.0 ..< 601.0.0` under semver and conflicts with any
                // corpus pinning 601 or 602 — which is most of them, since a
                // syntax-visitor package pins swift-syntax `exact:`. The open
                // range lets SwiftPM take whatever the user package already
                // resolved.
                entries.append(
                    ".package(url: \"https://github.com/swiftlang/swift-syntax.git\", "
                        + "\"600.0.0\" ..< \"700.0.0\")"
                )
            }

        case .interaction:
            // V2.0 M3.E.2 — interaction verify needs the v2.2.0 kit
            // surface (ActionSequenceFactory + StatefulGuard, shipped
            // alongside PropertyLawKit). swift-property-based is a
            // transitive dep — declared explicitly so the synthesized
            // workdir's Package.swift resolves without leaning on
            // the kit's own dep graph.
            entries = [
                ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
                swiftPropertyLawsDependencyLine
            ]

        case .interactionTCA:
            // Cycle 122 — interaction deps + TCA. The corpus is compiled
            // into the verifier target (direct source inclusion), so there
            // is no user-package path dependency — just CA for the macros
            // and runtime the co-compiled reducer needs.
            entries = [
                ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
                swiftPropertyLawsDependencyLine,
                ".package(url: "
                    + "\"https://github.com/pointfreeco/swift-composable-architecture.git\", "
                    + "from: \"1.15.0\")"
            ]

        case .interactionMobius:
            // Interaction deps + Mobius, pinned to an unreleased `master`
            // revision (the tags don't build under the current toolchain).
            entries = [
                ".package(url: \"https://github.com/x-sheep/swift-property-based.git\", from: \"1.0.0\")",
                swiftPropertyLawsDependencyLine,
                ".package(url: \"https://github.com/spotify/Mobius.swift.git\", "
                    + "revision: \"74baa7e07b86ae4c2673204a92230db397b8a6ae\")"
            ]
        }
        if let userPackage {
            entries.append(".package(path: \(escapedLiteral(userPackage.packagePath.path)))")
        }
        return entries
            .map { "        \($0)" }
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
    /// The interaction shape plus Spotify's Mobius (MobiusCore) — so the
    /// co-compiled `(Model, Event) -> Next<Model, Effect>` reducer + the
    /// stub's `import MobiusCore` resolve. Same direct-source-inclusion
    /// model as `.interactionTCA`. Pinned to an unreleased `master`
    /// revision: the tagged releases (0.5–0.7) don't compile under the
    /// current Swift toolchain; `master` HEAD does. Revisit when Spotify
    /// cuts a toolchain-compatible release.
    case interactionMobius = "interaction-mobius"
}
