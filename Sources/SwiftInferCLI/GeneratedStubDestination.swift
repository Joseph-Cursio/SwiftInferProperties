import Foundation

/// Where an accepted suggestion's generated file goes, and whether anything will build it.
///
/// ## The defect this closes
///
/// Every `discover --interactive` accept path composed its writeout as
/// `<packageRoot>/Tests/Generated/SwiftInfer/…`, unconditionally. **`Tests/Generated/` is
/// inside no SwiftPM target on any package**, because a target is `Tests/<Name>/` — so the
/// file was compiled by nothing, everywhere, and nothing said so. Measured on a minimal
/// conventional package (`Sources/Demo` + `Tests/DemoTests`) with a file of deliberate
/// garbage at `Tests/Generated/SwiftInfer/idempotence/f.swift`:
///
/// ```
/// swift build --build-tests  →  Build complete! (5.06 sec), exit 0, no diagnostic
/// ```
///
/// That is the confident-zero shape on the emit side: a reader who accepts nineteen
/// suggestions and runs `swift test` sees a green suite and concludes the laws passed.
/// Nothing built them. Issue #414, found walking SwiftMarkdownWiki through the pipeline —
/// whose targets are rooted at `SwiftMarkdownWiki/` and `SwiftMarkdownWikiTests/`, so the
/// Xcode-originated layout is where it was *noticed*, not where it is confined.
///
/// ## Why the manifest cannot finish the job alone
///
/// The obvious fix — *take the first `test` target's path* — is under-specified on the very
/// subject that produced the issue. SwiftMarkdownWiki declares **two** test targets and both
/// declare `dependencies: ["SwiftMarkdownWiki"]`, so the dependency graph narrows the
/// candidates to two and stops. The manifest **narrows but does not decide**, which is why
/// `--output-dir` is load-bearing rather than a convenience, and why the note names the
/// alternatives instead of pretending the choice was forced.
///
/// ## Degradation
///
/// Follows `TargetIsolation.sourceDirectory` and `TestTargetScope`: **every can't-answer arm
/// returns the legacy `Tests/Generated` path**, which is exactly what every caller did before
/// this existed. A manifest that cannot be read must not invent a destination. The difference
/// from before is that the arm now *says* the destination is unbuilt, which is the whole of
/// part 2 of the issue — a wrong default that announces itself is recoverable.
///
/// The manifest is checked for existence before anything is spawned, for the reason
/// `Discover+RunHelpers` records a measured regression for: `TestTargetScope.dump` shells out
/// unconditionally, and the unit fixtures that construct a package root with no `Package.swift`
/// would each pay a subprocess to be told nothing.
enum GeneratedStubDestination {

    /// The resolved destination for one `discover --interactive` run.
    struct Resolution: Equatable {
        /// The directory holding `SwiftInfer/` and `SwiftInferRefactors/` — i.e. what used
        /// to be hard-coded as `<packageRoot>/Tests/Generated`.
        let generatedRoot: URL

        /// `false` only when this is known to be built by nothing. An `--output-dir` the
        /// user named is `true`: the tool cannot verify their choice and does not second-
        /// guess it.
        let compiledWhereItSits: Bool

        /// One line for stderr, emitted once per run by the caller (which adds `note: `).
        let note: String
    }

    /// The legacy destination, preserved exactly for every arm that cannot do better.
    static func legacyRoot(packageRoot: URL) -> URL {
        packageRoot
            .appendingPathComponent("Tests")
            .appendingPathComponent("Generated")
    }

    /// Resolve the destination for a run that scanned `scanDirectory` inside `packageRoot`.
    ///
    /// - Parameter outputDirectoryOverride: `--output-dir`, which wins over everything. It
    ///   names the directory that receives the `SwiftInfer/` tree, not a package root.
    static func resolve(
        packageRoot: URL,
        scanDirectory: URL,
        outputDirectoryOverride: URL?
    ) -> Resolution {
        if let override = outputDirectoryOverride?.standardizedFileURL {
            return Resolution(
                generatedRoot: override,
                compiledWhereItSits: true,
                note: "generated files go to \(override.path) (--output-dir)"
            )
        }
        let manifest = packageRoot.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            return unbuiltResolution(packageRoot: packageRoot, reason: "no Package.swift at \(packageRoot.path)")
        }
        let module = module(forScanDirectory: scanDirectory, packageRoot: packageRoot)
        let candidates = rankedCandidates(packageRoot: packageRoot, module: module)
        guard let chosen = candidates.first else {
            return unbuiltResolution(
                packageRoot: packageRoot,
                reason: "Package.swift declares no test target whose directory exists"
            )
        }
        return Resolution(
            generatedRoot: chosen.directory.appendingPathComponent("Generated"),
            compiledWhereItSits: true,
            note: chosenNote(chosen: chosen, alternatives: Array(candidates.dropFirst()))
        )
    }

    // MARK: - Arms

    private static func unbuiltResolution(packageRoot: URL, reason: String) -> Resolution {
        let root = legacyRoot(packageRoot: packageRoot)
        return Resolution(
            generatedRoot: root,
            compiledWhereItSits: false,
            note: "generated files go to \(root.path), which NO SwiftPM target builds"
                + " (\(reason)) — `swift test` will not run them and will not say so."
                + " Move them into a test target, or pass --output-dir."
        )
    }

    private static func chosenNote(
        chosen: TestTargetScope.TestTargetLocation,
        alternatives: [TestTargetScope.TestTargetLocation]
    ) -> String {
        let head = "generated files go to \(chosen.directory.appendingPathComponent("Generated").path)"
            + " — test target '\(chosen.name)', from Package.swift"
        guard !alternatives.isEmpty else { return head }
        let names = alternatives.map(\.name).joined(separator: ", ")
        return head + "; \(alternatives.count) other test target(s) could also have taken it"
            + " (\(names)) — pass --output-dir to choose."
    }

    // MARK: - Ranking

    /// Test targets that may receive the writeout, best first.
    ///
    /// Dependency-reaching targets win outright, which is `TestTargetScope`'s rule and is
    /// sound rather than heuristic. **The tie-break among them is the `<Module>Tests` name**,
    /// and that is not the name rule `TestTargetScope` measured and rejected: there, a name
    /// was proposed as a *filter*, whose false negatives silently drop legitimate test
    /// targets. Here every candidate is already valid and one must be picked, so a name can
    /// only change which correct answer is given — and on a conventional package it gives the
    /// one the reader expects.
    private static func rankedCandidates(
        packageRoot: URL,
        module: String?
    ) -> [TestTargetScope.TestTargetLocation] {
        let all = TestTargetScope.testTargetLocations(exercising: module, packageRoot: packageRoot)
        let reaching = all.filter(\.reachesModule)
        let pool = reaching.isEmpty ? all : reaching
        let preferredName = module.map { "\($0)Tests" }
        return pool.sorted { precedes($0, $1, preferredName: preferredName) }
    }

    /// Total order, so a package with several candidates resolves identically on every run:
    /// the conventionally-named target first, then the shallowest path, then alphabetically.
    private static func precedes(
        _ lhs: TestTargetScope.TestTargetLocation,
        _ rhs: TestTargetScope.TestTargetLocation,
        preferredName: String?
    ) -> Bool {
        let lhsPreferred = lhs.name == preferredName
        let rhsPreferred = rhs.name == preferredName
        guard lhsPreferred == rhsPreferred else { return lhsPreferred }
        let lhsPath = lhs.directory.standardizedFileURL.path
        let rhsPath = rhs.directory.standardizedFileURL.path
        guard lhsPath.count == rhsPath.count else { return lhsPath.count < rhsPath.count }
        return lhsPath < rhsPath
    }

    // MARK: - Module

    /// The module the scan directory belongs to, according to the manifest.
    ///
    /// Longest match wins, for the reason `VerifyTargetInference.manifestModule` gives: one
    /// target's directory may contain another's, and the shorter prefix would otherwise claim
    /// it. Nil — not a guess — when no declared target contains the scan directory, which is
    /// the `--sources`-at-an-arbitrary-folder case; the ranking then falls back to every test
    /// target rather than to none.
    static func module(forScanDirectory scanDirectory: URL, packageRoot: URL) -> String? {
        let scan = scanDirectory.standardizedFileURL.path
        let root = packageRoot.standardizedFileURL
        let declared = TargetIsolation.declaredTargetDirectories(packageRoot: packageRoot)
            .sorted { $0.path.count > $1.path.count }
        for candidate in declared {
            let directory = root.appendingPathComponent(candidate.path).standardizedFileURL.path
            if scan == directory || scan.hasPrefix(directory + "/") { return candidate.name }
        }
        return nil
    }
}
