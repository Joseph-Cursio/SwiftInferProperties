import Foundation

/// Which SwiftPM target does a SemanticIndex entry's source file live in?
///
/// The inverse of `TargetDirectory.resolve`, which maps `--target Foo` to `Sources/Foo/`. This
/// reads `Sources/Foo/Bar.swift` back to `Foo`, and is exactly as trustworthy as the forward
/// direction already is: both assume the conventional layout, and both check the directory is
/// really there rather than trusting the name.
///
/// ## Why this exists
///
/// `--target` is what makes the verifier path-depend on the user's package and `@testable`-import
/// the module. Without it the stub gets neither, so **any carrier the user defined is out of
/// reach** — the generated law references types the stub cannot see and the build fails.
///
/// `--target`'s help text has claimed since v1.149 that it "resolves the target from the
/// SemanticIndex entry", and nothing did. The flag was optional, its absence was silent, and the
/// cost was a whole survey: `verify --all-from-index` over this repo returned **114
/// `measured-error | build-failed`** and zero verdicts, which reads as a limit of the tool and was
/// a missing flag. The same entries verify 9-of-10 once the module is supplied.
///
/// ## What it deliberately will not do
///
/// The file must sit at `<packageRoot>/Sources/<module>/…` — a **direct** child of the package
/// root's `Sources`. A module inside a nested package (`Packages/Sub/Sources/Mod/…`) returns nil,
/// because the wiring this feeds path-depends on `packageRoot` and resolves the product from *its*
/// manifest: naming `Mod` there would emit a `.product` no manifest declares, and trade a build
/// failure that says "cannot find type" for one that says "no such product". Both fail; only the
/// first points at the real problem.
///
/// Returning nil restores the previous behaviour exactly, so every non-conventional layout is no
/// worse off than before.
enum VerifyTargetInference {

    /// The module owning `location`, or nil when it cannot be established.
    ///
    /// - Parameters:
    ///   - location: a `SemanticIndexEntry.location` — an absolute path with a trailing `:line`
    ///     (and sometimes `:column`).
    ///   - packageRoot: the package the verifier will path-depend on.
    static func module(forLocation location: String, packageRoot: URL) -> String? {
        let path = sourcePath(from: location)
        // The manifest wins wherever it *could* disagree, and only there. See
        // `manifestMayRelocateTargets` for why that gate is a text scan and not the dump.
        if manifestMayRelocateTargets(packageRoot: packageRoot),
           let declared = manifestModule(forPath: path, packageRoot: packageRoot) {
            return declared
        }
        if let conventional = conventionalModule(forPath: path, packageRoot: packageRoot) {
            return conventional
        }
        // Only now pay for the manifest. `dump-package` is a subprocess, this runs once per
        // index entry, and a survey has hundreds — the first version consulted the manifest
        // FIRST and took the ~33-second fast suite past ten minutes. Caching the dump did not
        // rescue it, because the cost is invoking SwiftPM at all on paths that never needed
        // it. Cheap structural check first, subprocess only when the convention does not
        // answer, which is the ordering `TestTargetScope` records a measured reason for.
        return manifestModule(forPath: path, packageRoot: packageRoot)
    }

    /// Could this package's manifest put a target somewhere the path convention would misread?
    ///
    /// **A text scan of `Package.swift`, deliberately — not the dump.** The dump is
    /// authoritative and this is not; its only job is to decide whether paying for the
    /// authoritative answer can change anything. A false positive costs one memoised
    /// subprocess for that package root; a false negative cannot happen, because a target
    /// cannot be relocated without the word `path` appearing in the manifest.
    ///
    /// Why a gate at all, rather than consulting the manifest first as `manifestModule`'s own
    /// doc comment used to claim happened: the dump is memoised per package root, and the fast
    /// suite creates many temp fixture roots, so *manifest-first* is one subprocess per package
    /// rather than one per entry — recoverable, but paid by every conventional package for a
    /// question only unconventional ones can answer differently.
    ///
    /// `.package(path:)` lines are excluded because a local dependency relocates nothing in
    /// *this* manifest's targets, and every fixture package here declares one — admitting them
    /// would make the gate true everywhere and cost exactly what it exists to avoid.
    ///
    /// ## The defect this fixes
    ///
    /// swift-system declares `.target(name: "SystemPackage", path: "Sources/System")`. The path
    /// convention reads `Sources/System/FilePath.swift` back as module `System`, which is not a
    /// target and not a product — so `verify --all-from-index` quarantined **21 of 41 picks** as
    /// `unsupported-carrier: System is not a library product of swift-system`. That reads as a
    /// carrier gap and was a module-resolution bug. GRDB (`path: "GRDB"`, outside `Sources/`)
    /// was already handled, because there the convention *fails* and falls through; swift-system
    /// is the harder case, where the convention **succeeds and is wrong**.
    private static func manifestMayRelocateTargets(packageRoot: URL) -> Bool {
        let key = packageRoot.standardizedFileURL.path
        if let cached = relocationGateCache.value(forKey: key) { return cached }
        let manifest = packageRoot.appendingPathComponent("Package.swift")
        let text = (try? String(contentsOf: manifest, encoding: .utf8)) ?? ""
        let answer = text.components(separatedBy: "\n").contains { line in
            guard !line.contains(".package(") else { return false }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("path:") || trimmed.contains(", path:")
        }
        relocationGateCache.store(answer, forKey: key)
        return answer
    }

    /// Memoised per package root, for the reason `TargetIsolation.DumpCache` records: this is
    /// called once per index entry and a survey has hundreds. Reading one small file that many
    /// times is cheaper than a subprocess and still not free.
    private static let relocationGateCache = RelocationGateCache()

    private final class RelocationGateCache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: Bool] = [:]

        func value(forKey key: String) -> Bool? {
            lock.lock()
            defer { lock.unlock() }
            return entries[key]
        }

        func store(_ value: Bool, forKey key: String) {
            lock.lock()
            entries[key] = value
            lock.unlock()
        }
    }

    /// The `Sources/<module>/…` rule — the original implementation, unchanged.
    private static func conventionalModule(forPath path: String, packageRoot: URL) -> String? {
        let sources = packageRoot.appendingPathComponent("Sources")
        let prefix = sources.standardizedFileURL.path + "/"
        guard path.hasPrefix(prefix) else { return nil }

        let remainder = String(path.dropFirst(prefix.count))
        // The module is the first component, and there must be something after it — a file
        // sitting directly in `Sources/` (`Sources/main.swift`) belongs to no target directory.
        let components = remainder.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count >= 2 else { return nil }
        let candidate = String(components[0])
        guard !candidate.isEmpty else { return nil }

        // Confirm rather than assume, for the same reason `TargetDirectory.resolve` does: a name
        // parsed out of a path is a guess until something on disk agrees with it. Calling that
        // type's own check rather than repeating it is what makes this doc comment's claim of
        // kinship with the forward direction true instead of merely asserted.
        guard TargetDirectory.isDirectory(sources.appendingPathComponent(candidate)) else {
            return nil
        }
        return candidate
    }

    /// The module owning `path` according to the manifest, or nil when the manifest cannot
    /// answer.
    ///
    /// **Consulted before the path-shape rule when — and only when — `manifestMayRelocateTargets`
    /// says the manifest could disagree with it.** The manifest is authoritative and the path
    /// shape is a convention, so where both can answer the manifest must win; the gate exists
    /// because paying for the authoritative answer is a subprocess and most packages cannot
    /// disagree. For a conventional package the two agree anyway. For GRDB, which declares
    /// `path: "GRDB"`, this is the only thing that can answer. For swift-system, which declares
    /// `path: "Sources/System"` for target `SystemPackage`, this is the only thing that can
    /// answer *correctly* — the convention answers `System`, confidently and wrongly.
    ///
    /// **Longest match wins.** Nothing stops one target's directory containing another's
    /// (`path: "Sources"` alongside `Sources/Core`), and the shorter prefix would otherwise
    /// claim every file of the longer. Sorting by descending path length makes the more
    /// specific declaration win, which is what SwiftPM itself does.
    ///
    /// Nil, not a guess, when the manifest is unreadable or names no containing target — the
    /// caller then falls through to the `Sources/<module>/` rule, which is exactly the
    /// behaviour that existed before this was added.
    private static func manifestModule(forPath path: String, packageRoot: URL) -> String? {
        let root = packageRoot.standardizedFileURL.path
        let candidates = TargetIsolation.declaredTargetDirectories(packageRoot: packageRoot)
            .sorted { $0.path.count > $1.path.count }
        for candidate in candidates {
            let directory = URL(fileURLWithPath: root)
                .appendingPathComponent(candidate.path)
                .standardizedFileURL
            guard path.hasPrefix(directory.path + "/") else { continue }
            // Confirm on disk, for the reason the path-shape rule below gives: a name taken
            // from a manifest is still a guess until something on disk agrees with it.
            guard TargetDirectory.isDirectory(directory) else { continue }
            return candidate.name
        }
        return nil
    }

    /// Strip the `:line` / `:line:column` suffix a location carries.
    ///
    /// Drops **only** trailing components that are entirely digits, at most twice. A path is not
    /// obliged to avoid colons, so `split(separator: ":").first` would silently truncate one that
    /// contains any — and a wrong path resolves to a wrong module or to nil, neither of which
    /// announces itself.
    static func sourcePath(from location: String) -> String {
        var path = location
        for _ in 0 ..< 2 {
            guard let colon = path.lastIndex(of: ":") else { break }
            let suffix = path[path.index(after: colon)...]
            guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { break }
            path = String(path[..<colon])
        }
        return URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
