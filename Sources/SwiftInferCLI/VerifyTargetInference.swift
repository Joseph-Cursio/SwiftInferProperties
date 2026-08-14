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
    /// **Consulted BEFORE the path-shape rule, because the manifest is authoritative and the
    /// path shape is a convention.** For a conventional package the two agree, so this changes
    /// nothing; for GRDB, which declares `path: "GRDB"`, it is the only thing that can answer.
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
