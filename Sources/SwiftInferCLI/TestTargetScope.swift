import Foundation

/// Which test targets could be exercising the production target being scanned.
///
/// ## The defect this closes
///
/// `discover --target X` resolves production code to `Sources/X/`, but TestLifter's
/// scan directory was `<package-root>/Tests/` **wholesale** — there was no
/// `Tests/<Target>Tests/` counterpart to the `Sources/<target>/` convention the
/// tool otherwise honours. So every lifted law was attributed to whichever target
/// you happened to name, and running `discover` once per target produced the *same*
/// lifted rows six times over.
///
/// The symptom is that it looks like signal: the same four rows appeared
/// byte-identical on all six targets, citing `render(suggestion)` and
/// `Set(declarations).count`, symbols that exist in neither. On
/// `SwiftInferKitEvidence` and `SwiftInferMacroImpl`, **4 of 4** suggestions were
/// about other targets' code — on targets whose conformance scan reports *zero
/// carriers*.
///
/// **Measured for THIS fix: Strong-tier rows 26 → 16**
/// (`docs/measurements/roadtest-self-dogfood-2026-08-08.md` §1.1; A/B with one binary,
/// since `--test-dir Tests` reproduces the pre-fix default exactly). All 10 removed
/// rows are lifted rows and no non-lifted row moved.
///
/// §1 of that document separately measured **26 → 7** by narrowing to
/// `Tests/<Target>Tests/`. That number is *too good* and this type deliberately does
/// not reach it — see below.
///
/// ## Why dependency, not name
///
/// The obvious fix — scope to `Tests/<Target>Tests/` — is a **bound, not a fix**.
/// `SwiftInferIntegrationTests` legitimately exercises `SwiftInferCLI`, and a
/// name rule cannot see that. The manifest can: a test target that (transitively)
/// depends on the scanned target may be testing it, and one that does not, cannot be.
///
/// ## Transitive, deliberately
///
/// SwiftPM makes you declare what you import, so *direct* dependencies are already
/// sufficient on most packages — but only by convention. A test target that imports
/// `SwiftInferCLI` and exercises `SwiftInferCore` code through it declares only the
/// former, and a direct-only rule would drop it. That is a false **negative**, the
/// direction this catalog treats as the bad one, so the closure is transitive.
///
/// It is not merely permissive-by-default: on this repo the transitive closure still
/// collapses the leaf targets to their own tests (`SwiftInferKitEvidence` and
/// `SwiftInferMacroImpl` are reached by exactly one test target each, because nothing
/// else depends on them, and both go 4 → 0), while `SwiftInferCore` stays reached by
/// all eight — which is *correct*, since everything genuinely does depend on Core, and
/// one of the rows it keeps (`merge(merge(log))`) really is about `Decisions.merge`,
/// which lives in Core. The fix lands precisely on the demonstrably-wrong cases and
/// leaves the broad-but-right one broad. That is why it stops at 16 rather than 7.
///
/// ## The honest limit
///
/// This is a sound **over-approximation, not an attribution**. It answers *could this
/// test target be exercising that module*, and for a base module the answer is
/// legitimately "all of them" — so a law lifted from a CLI test body still appears on
/// `SwiftInferCore` wherever the dependency graph permits, even when the symbol it
/// names is CLI's. Closing that needs the lifted law attributed to the target
/// **declaring the symbol it mentions**, which is symbol resolution and a different
/// feature. Recorded as the remaining gap rather than approximated with a name
/// heuristic — that is the thing measured and rejected above.
///
/// ## Degradation
///
/// Follows `PackageProductResolver`: any failure — no manifest, `dump-package`
/// errors, JSON shape drift — returns `nil`, and the caller falls back to today's
/// whole-`Tests/` behaviour. **An empty result is not a failure**: a target that no
/// test target reaches legitimately lifts nothing, and folding that into the fallback
/// would reintroduce exactly the bug this type exists to close.
public enum TestTargetScope {

    // MARK: - Manifest shape

    private struct DumpedPackage: Decodable {
        let targets: [DumpedTarget]
    }

    private struct DumpedTarget: Decodable {
        let name: String
        let type: String
        let path: String?
        let dependencies: [DumpedDependency]?

        var isTest: Bool { type == "test" }
    }

    /// A dependency edge. SwiftPM emits `byName`/`target` for in-package edges and
    /// `product` for cross-package ones; only the first two can name a target in
    /// this manifest, and a `product` entry is ignored rather than treated as a
    /// miss — `PropertyLawKit` is not a target here and never resolves to a path.
    ///
    /// Each value is an array whose first element is the name (`byName` pads the
    /// rest with nulls), so the decoder takes `[String?]` and reads element 0.
    private struct DumpedDependency: Decodable {
        let byName: [String?]?
        let target: [String?]?

        var targetName: String? {
            if let name = byName?.first, let name { return name }
            if let name = target?.first, let name { return name }
            return nil
        }
    }

    // MARK: - Resolution

    /// Directories of the test targets that could be exercising `module`.
    ///
    /// Returns `nil` when the manifest cannot be read — the caller must then fall
    /// back to the previous whole-`Tests/` behaviour rather than lifting nothing.
    /// Returns an **empty array** when the manifest is readable and no test target
    /// reaches `module`; that is an answer, not a failure.
    ///
    /// Only directories that exist on disk are returned, so a manifest naming a
    /// target whose sources have been moved away cannot produce a phantom scan root.
    public static func testDirectories(
        exercising module: String,
        packageRoot: URL
    ) -> [URL]? {
        guard let dumped = dump(packageRoot: packageRoot) else { return nil }

        let targetsByName = Dictionary(dumped.targets.map { ($0.name, $0) }) { first, _ in first }
        // An unknown module is "cannot answer", NOT "nothing tests it". `--sources`
        // can point at any directory inside a package — a folder that is not a
        // declared target, or a target whose manifest `path` moves it off the
        // `Sources/<name>` convention this call derives the name from. Returning
        // `[]` there would silently lift nothing; `nil` falls back to whole-`Tests/`,
        // which is the pre-fix behaviour and safe.
        guard targetsByName[module] != nil else { return nil }

        let fileManager = FileManager.default

        let reaching = dumped.targets
            .filter(\.isTest)
            .filter { reaches(module, from: $0.name, in: targetsByName) }

        return reaching
            .map { directory(of: $0, packageRoot: packageRoot) }
            .filter { fileManager.fileExists(atPath: $0.path) }
            .sorted { $0.path < $1.path }
    }

    /// Transitive reachability from `origin` to `module` over in-package target
    /// dependency edges. Iterative with an explicit visited set: a manifest is
    /// user-authored input, and a dependency cycle must not become a stack
    /// overflow in a tool whose whole posture is "never crash on the user's code".
    private static func reaches(
        _ module: String,
        from origin: String,
        in targetsByName: [String: DumpedTarget]
    ) -> Bool {
        var visited: Set<String> = [origin]
        var frontier = [origin]

        while let current = frontier.popLast() {
            let dependencies = targetsByName[current]?.dependencies ?? []
            for name in dependencies.compactMap(\.targetName) {
                if name == module { return true }
                // Only follow edges that name a target in THIS manifest; a
                // `.product` edge to another package cannot lead back here.
                guard targetsByName[name] != nil, visited.insert(name).inserted else {
                    continue
                }
                frontier.append(name)
            }
        }
        return false
    }

    /// A target's source directory: its explicit `path` when the manifest sets one,
    /// otherwise SwiftPM's `Tests/<name>` convention for test targets.
    ///
    /// An explicit `path` is resolved against the package root and may be relative
    /// or absolute, matching how SwiftPM itself reads it.
    private static func directory(of target: DumpedTarget, packageRoot: URL) -> URL {
        guard let path = target.path, !path.isEmpty else {
            return packageRoot
                .appendingPathComponent("Tests")
                .appendingPathComponent(target.name)
        }
        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return packageRoot.appendingPathComponent(path)
    }

    private static func dump(packageRoot: URL) -> DumpedPackage? {
        // Via `DrainedProcess`, matching `PackageProductResolver`: the wait-then-read
        // shape deadlocks on a large manifest dump (see #170).
        guard let data = DrainedProcess.standardOutputViaEnv(
            ["swift", "package", "dump-package", "--package-path", packageRoot.path]
        ) else { return nil }
        return try? JSONDecoder().decode(DumpedPackage.self, from: data)
    }
}
