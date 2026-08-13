import Foundation

/// The default actor isolation a SwiftPM target is compiled under, read from the manifest.
///
/// ## The defect this closes
///
/// `scaffold-kit-suites` reported **21 carriers / 64 laws emitted live, `0 commented out`**
/// on `SwiftFormatRuleStudioCore` — a 100% derivation rate, the best on record. The emitted
/// file produced **132 compile errors and ran 0 of the 64 laws**
/// (`docs/measurements/exploratory-swiftformatrulestudio.md` §2).
///
/// One cause, and it is one line of that package's manifest:
/// `.defaultIsolation(MainActor.self)` makes every unannotated type's conformances
/// MainActor-isolated, and `check<Protocol>PropertyLaws` requires `Value: Sendable`:
///
/// ```
/// error: main actor-isolated conformance of 'FormatOption' to 'Equatable' cannot satisfy
///        conformance requirement for a 'Sendable' type parameter  [#IsolatedConformances]
/// ```
///
/// **The gate the emitter applied was *can I derive a generator*; the question that decides
/// whether the file is usable is *will this compile*.** The deciding fact was sitting in
/// `Package.swift`, a file this repo already shells out to read for `TestTargetScope`.
///
/// ## Target-level, and deliberately coarse
///
/// `dump-package` reports the setting **per target**, so this reads the scanned target's own
/// value rather than assuming a package-wide one — a package may set it on some targets and
/// not others.
///
/// It is a sound **over-approximation**: a type declared `nonisolated` escapes default
/// isolation and would compile, and nothing here can see that, because the scanner records no
/// isolation modifiers (`IndexedTypeShape` has no such field). So a `nonisolated` carrier in a
/// MainActor-default target is blocked when it need not be.
///
/// **The direction is chosen, not conceded.** Over-blocking costs a reader one uncomment on a
/// carrier that would have worked, and it is disclosed with a reason. Under-blocking is the
/// measured bug: a file that does not compile, under a count claiming no gaps. Measured cost
/// on the subject that produced the finding: **0 of 43 public value types** are declared
/// `nonisolated`, so the over-approximation is free there. Reaching per-carrier precision
/// needs the scanner to record isolation modifiers, which is a scanner change and is recorded
/// as the remaining gap rather than approximated with a name heuristic
/// (falsifier: `IndexedTypeShape.isNonisolated`).
///
/// ## Degradation
///
/// Follows `TestTargetScope` and `PackageProductResolver`: **every can't-answer arm returns
/// `nil`**, and `nil` means *emit exactly as before*. A missing manifest, a `dump-package`
/// failure, JSON shape drift, a `--sources` run naming no manifest target — all fall back to
/// today's behaviour rather than blocking.
///
/// That asymmetry is load-bearing and is the opposite of `TestTargetScope`'s. There, a broken
/// read that returned `[]` would silently switch lifting off. Here, a broken read that
/// returned `"MainActor"` would comment out **every carrier on every package**, turning an
/// unreadable manifest into a total coverage gap — so the failure direction is chosen to be
/// the one that changes nothing.
public enum TargetIsolation {

    // MARK: - Manifest shape

    // Mirrors only what this question needs. `dump-package` renders a `SwiftSetting` as a
    // single-key object tagged by kind, with the payload under `_0`:
    //
    //   {"kind": {"defaultIsolation": {"_0": "MainActor"}}, "tool": "swift"}
    //
    // Decoded structurally rather than by string-matching the raw JSON, so a target that
    // merely *mentions* the word in a path or a name cannot be read as setting it.
    private struct DumpedPackage: Decodable {
        let targets: [DumpedTarget]
    }

    private struct DumpedTarget: Decodable {
        let name: String
        let settings: [DumpedSetting]?
    }

    private struct DumpedSetting: Decodable {
        let kind: DumpedSettingKind
        /// `"swift"`, `"linker"`, `"c"`, `"cxx"`. A linker setting cannot carry isolation,
        /// and filtering on it keeps a future same-named key in another tool from matching.
        let tool: String?
    }

    private struct DumpedSettingKind: Decodable {
        let defaultIsolation: DumpedIsolationPayload?
    }

    private struct DumpedIsolationPayload: Decodable {
        // swiftlint:disable:next identifier_name
        let _0: String?
    }

    // MARK: - Query

    /// The default isolation of `targetName`, or `nil` when the question cannot be answered.
    ///
    /// Returns the isolation's spelling as the manifest reports it (`"MainActor"`), not a
    /// closed enum: the set of legal values is SwiftPM's to grow, and a value this code has
    /// never heard of is still a value the emitter should report verbatim rather than drop.
    ///
    /// `nil` covers all of: no manifest, `dump-package` failed, JSON drift, no such target,
    /// and **the target sets no default isolation at all** — the common case. The caller
    /// treats every one of them as "emit as before", so they do not need separating.
    public static func defaultIsolation(packageRoot: URL, targetName: String) -> String? {
        guard let dumped = dump(packageRoot: packageRoot) else { return nil }
        guard let target = dumped.targets.first(where: { $0.name == targetName }) else {
            return nil
        }
        return target.settings?
            .first { $0.tool == "swift" && $0.kind.defaultIsolation != nil }?
            .kind.defaultIsolation?._0
    }

    /// Walk up from a scanned source directory to the nearest `Package.swift`.
    ///
    /// Mirrors the walk `discover` already does for `.swiftinfer/` and config, rather than
    /// assuming `Sources/<target>/../..`: a manifest may place a target anywhere via `path`.
    public static func packageRoot(containing directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        while candidate.path != "/" {
            let manifest = candidate.appendingPathComponent("Package.swift")
            if FileManager.default.fileExists(atPath: manifest.path) { return candidate }
            candidate = candidate.deletingLastPathComponent()
        }
        return nil
    }

    // MARK: - Subprocess

    // A third independent `dump-package` invocation, after `TestTargetScope` and
    // `PackageProductResolver`, each with its own private model of the same JSON. Deliberately
    // not unified here: sharing a parse means threading a cache through three unrelated call
    // paths, and `TestTargetScope` documents a measured perf reason for calling only after a
    // cheaper check has passed. The duplication is a known cost, recorded rather than hidden.
    private static func dump(packageRoot: URL) -> DumpedPackage? {
        let manifest = packageRoot.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        guard let data = DrainedProcess.standardOutputViaEnv([
            "swift", "package", "dump-package", "--package-path", packageRoot.path
        ]) else { return nil }
        return try? JSONDecoder().decode(DumpedPackage.self, from: data)
    }
}
