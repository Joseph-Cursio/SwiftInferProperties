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
        /// The target's declared `path:`, relative to the package root, or `nil` when the
        /// manifest omits it and SwiftPM's `Sources/<name>` default applies.
        let path: String?
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

    /// Where `targetName`'s sources actually live, resolved against the manifest.
    ///
    /// **`Sources/<target>` is a DEFAULT, not a rule, and assuming it made whole packages
    /// unreachable.** A manifest may place a target anywhere via `path:` — the fact
    /// `packageRoot(containing:)` below already states, and works around, while the callers
    /// that resolve a target *forward* assumed the opposite.
    ///
    /// **Measured on GRDB `b83108d10` (2026-08-14):** it declares `path: "GRDB"`, so its 167
    /// sources sit at repo root and `prove-then-show --target GRDB` scanned a directory that
    /// does not exist. The package could not be surveyed **at all** — not a partial gap, and
    /// not a gap the tool reported as one. GRDB is widely used, so the population is not
    /// exotic; the run recorded in `docs/measurements/exploratory-swiftformat-grdb.md` §7 was
    /// obtained by moving the sources by hand.
    ///
    /// **The failure direction is deliberate and matches `defaultIsolation` above: every
    /// can't-answer arm returns the `Sources/<target>` default**, which is exactly what every
    /// caller did before this existed. A broken manifest read must not invent a path — it
    /// must leave behaviour unchanged — because this resolves the directory a scan then walks,
    /// and answering wrongly turns a working package into an empty scan that reports nothing
    /// to suggest rather than an error.
    ///
    /// Returned as an absolute URL under `packageRoot`. A declared `path` is relative to the
    /// package root by SwiftPM's definition, so it is appended rather than resolved against
    /// the working directory.
    public static func sourceDirectory(packageRoot: URL, targetName: String) -> URL {
        let fallback = packageRoot
            .appendingPathComponent("Sources")
            .appendingPathComponent(targetName)
        guard let dumped = dump(packageRoot: packageRoot),
              let target = dumped.targets.first(where: { $0.name == targetName }),
              let declared = target.path,
              !declared.isEmpty else {
            return fallback
        }
        return packageRoot.appendingPathComponent(declared)
    }

    /// Every target the manifest declares, with the directory each one actually occupies.
    ///
    /// The **inverse** of `sourceDirectory` above, and it has to exist for the same reason: a
    /// scan resolved through the manifest produces entries whose paths no longer match
    /// `Sources/<module>/`, so reading a module back out of a path must consult the manifest
    /// too. Fixing only the forward direction is what made native GRDB *worse* than the
    /// hand-staged arm — the scan reached 307 picks and then every stub lost its
    /// `@testable import`, trading `no such directory` for `cannot find type 'SQL' in scope`.
    ///
    /// Effective path, not declared path: a target with no `path:` reports `Sources/<name>`,
    /// so a caller matching against this list needs no special case for the default layout.
    ///
    /// Empty when the manifest cannot be read, which leaves every caller on its previous
    /// path-shape rule.
    public static func declaredTargetDirectories(packageRoot: URL) -> [(name: String, path: String)] {
        guard let dumped = dump(packageRoot: packageRoot) else { return [] }
        return dumped.targets.map { target in
            let declared = target.path.flatMap { $0.isEmpty ? nil : $0 }
            return (name: target.name, path: declared ?? "Sources/\(target.name)")
        }
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
    /// Memoised per package root, including the failures.
    ///
    /// **This cache is not an optimisation, it is a correctness-of-cost fix.** The three
    /// original callers each dumped once per *run*. `VerifyTargetInference.module` calls
    /// `declaredTargetDirectories` once per *index entry*, and a survey has hundreds — so the
    /// first version of that change spawned a `swift package dump-package` subprocess per row
    /// and took the ~33-second fast suite past **ten minutes** before it was killed. Measured,
    /// not predicted: the slowdown is what surfaced it.
    ///
    /// Failures are cached too. A missing or unparseable manifest is a property of the
    /// package, and re-spawning a subprocess to be told `nil` again is the same defect wearing
    /// a different answer.
    ///
    /// Keyed on the standardised path so `/a/b` and `/a/b/` share an entry. A manifest edited
    /// mid-process keeps the stale answer, which is correct for this process: every consumer
    /// resolves paths against the manifest as it was when the run began, and a survey that
    /// changed layout halfway through would be less coherent, not more.
    private final class DumpCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: DumpedPackage?] = [:]

        func value(forKey key: String, compute: () -> DumpedPackage?) -> DumpedPackage? {
            lock.lock()
            if let cached = entries[key] {
                lock.unlock()
                return cached
            }
            lock.unlock()
            // Computed OUTSIDE the lock: `dump-package` is a subprocess and holding a lock
            // across it would serialise the survey's whole TaskGroup on one manifest read.
            // Two racing callers may both compute; they compute the same answer, and a
            // duplicated subprocess is cheaper than a serialised survey.
            let computed = compute()
            lock.lock()
            entries[key] = computed
            lock.unlock()
            return computed
        }
    }

    private static let dumpCache = DumpCache()

    private static func dump(packageRoot: URL) -> DumpedPackage? {
        let key = packageRoot.standardizedFileURL.path
        return dumpCache.value(forKey: key) { uncachedDump(packageRoot: packageRoot) }
    }

    private static func uncachedDump(packageRoot: URL) -> DumpedPackage? {
        let manifest = packageRoot.appendingPathComponent("Package.swift")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        guard let data = DrainedProcess.standardOutputViaEnv([
            "swift", "package", "dump-package", "--package-path", packageRoot.path
        ]) else { return nil }
        return try? JSONDecoder().decode(DumpedPackage.self, from: data)
    }
}
