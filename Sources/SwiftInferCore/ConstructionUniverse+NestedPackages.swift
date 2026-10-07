/// Which nested packages' files are in the construction universe: **those the root compiles** —
/// the shared spec's amendment B, implemented word for word in SwiftProjectLint too, and pinned in
/// both repos by the shared `construction-universe-cases.json`.
///
/// A *nested package* is a directory below the root (never the root itself) that holds a
/// manifest — a `Package.swift` whose first line is a tools-version comment (amendment F,
/// `ConstructionUniverse+Manifests.swift`). Every file belongs to the nearest one above it, or to
/// the root's own package when there is none; the root's own files are always in the universe,
/// and a nested package's are only when the root reaches it:
///
/// - **The root has a manifest**: the closure of its local path dependencies. Each manifest's
///   `.package(path:)` values (`ConstructionUniverse+ManifestReader.swift`) are resolved from that
///   manifest's directory, standardised, then resolved through symlinks and compared by that
///   canonical location (amendments H and Q), and followed transitively — **by path**, to
///   `<dir>/Package.swift` on disk, even under a `Tests` / `*Tests` / hidden / pruned directory the
///   walk never enters (amendment I). A directory's dependencies are the union over its
///   `Package.swift` and every `Package@swift-*.swift` beside it (amendment O), and a nested package
///   holding one of its targets' `path:` is reached too (amendment P: `.target(name: "Core", path:
///   "Core/Sources/Core")` compiles `Core/`'s files as the root's own). A manifest in the closure
///   that passes `path:` anything but a string literal — to a dependency or a target — may depend
///   on any of them, so then **every** nested package is in (any doubt includes), and so does one
///   that exists and cannot be read. A path that leaves the root is ignored: the universe never
///   does.
/// - **It has none** — an Xcode app's folder, a workspace folder — **or an `*.xcodeproj` /
///   `*.xcworkspace` sits beside it** (amendment G): an Xcode project compiles local packages no
///   manifest names, and nothing cheap says which, so every nested package is in.
///
/// ## Why bound it
///
/// A table built from every nested package over-refutes a namesake the root never compiles. This
/// repo's own `fixtures/*/Package.swift` are packages its manifest never names, and an unrelated
/// `Demo/` package declaring a top-level `Row` that mints a `UUID` refuted the root's plain
/// `Row(n:)` — `discover --effect-annotations` stopped advising a `make(n:)` that main advised,
/// over a package the scan never judged.
extension ConstructionUniverse {

    /// The nested packages whose files are in the universe: every one of `nestedPackages` when the
    /// root has no manifest or the closure meets doubt, else the closure's packages — which may
    /// include one the walk never entered (amendment I), whose own files the predicate rejects.
    ///
    /// - Parameters:
    ///   - nestedPackages: root-relative directories (no trailing `/`) that hold a manifest, as the
    ///     walk found them.
    ///   - rootHasManifest: whether the root itself holds one — `false` too when an Xcode project
    ///     sits beside it (amendment G).
    ///   - judgedPackages: the root-relative nested packages that hold a file the run judges
    ///     (amendment J). Each is in, with its own closure, read under the same doubt rules.
    ///   - rootPath: the root's absolute path, resolved; every dependency and target path must lie
    ///     under it once resolved itself.
    ///   - resolvingSymlinks: an absolute path with every symlink resolved and, on a volume that
    ///     folds case, its on-disk letter case — the resolution the root's path went through
    ///     (amendments H and Q). The identity for an in-memory tree.
    ///   - packagesContaining: the root-relative directories at or above a resolved root-relative
    ///     location that hold a manifest (amendment P). `nil` means the walked packages that do,
    ///     for an in-memory tree.
    ///   - manifests: what a root-relative directory (`""` is the root) holds — its `Package.swift`
    ///     and every `Package@swift-*.swift` beside it, or nothing when it is no package. Read BY
    ///     PATH, whether or not the walk entered the directory (amendment I).
    public static func compiledNestedPackages(
        _ nestedPackages: Set<String>,
        rootHasManifest: Bool,
        judgedPackages: Set<String> = [],
        rootPath: String,
        resolvingSymlinks: (String) -> String = \.self,
        packagesContaining: ((String) -> [String])? = nil,
        manifests: (String) -> [Manifest]
    ) -> Set<String> {
        guard rootHasManifest, !nestedPackages.isEmpty else { return nestedPackages }
        // Each walked package by where it resolves (amendment Q): a dependency or a target path
        // reaches it by location, never by spelling.
        var packageAt: [String: String] = [:]
        for package in nestedPackages {
            let location = resolve(package, from: "", rootPath: rootPath, with: resolvingSymlinks)
            if let location { packageAt[location] = package }
        }
        let containing = packagesContaining ?? { location in
            packageAt.keys.filter { location == $0 || location.hasPrefix($0 + "/") }
        }
        var reached: Set<String> = []
        // The root's closure, and each judged package's own (amendment J): a scan of `Examples/`
        // over an uncompiled `Examples/Demo` judges Demo's functions, so it builds with Demo's types.
        let seeds = judgedPackages.compactMap { resolve($0, from: "", rootPath: rootPath, with: resolvingSymlinks) }
        var visited = Set([""] + seeds)
        var pending = visited.sorted(by: >)
        while let directory = pending.popLast() {
            let read = manifests(directory)
            if !directory.isEmpty, !read.isEmpty { reached.insert(packageAt[directory] ?? directory) }
            guard let literals = literals(of: read) else { return nestedPackages }
            let resolvedDependencies = literals.dependencies.compactMap {
                resolve($0, from: directory, rootPath: rootPath, with: resolvingSymlinks)
            }
            // A nested package holding a target's `path:` is compiled by that target (amendment P).
            let targetLocations = literals.targetPaths.compactMap {
                resolve($0, from: directory, rootPath: rootPath, with: resolvingSymlinks)
            }
            let targetPackages = targetLocations.flatMap(containing)
            for location in resolvedDependencies + targetPackages where visited.insert(location).inserted {
                pending.append(location)
            }
        }
        return reached
    }

    /// The nested package `relativePath` belongs to — the nearest of `nestedPackages` above it —
    /// or `nil` when it belongs to the root's own package.
    public static func owningPackage(of relativePath: String, among nestedPackages: Set<String>) -> String? {
        owningPackage(of: relativePath, where: nestedPackages.contains)
    }

    /// The nearest directory above `relativePath` that `isPackage` accepts, or `nil`.
    static func owningPackage(of relativePath: String, where isPackage: (String) -> Bool) -> String? {
        var directories = relativePath.split(separator: "/").dropLast().map(String.init)
        while !directories.isEmpty {
            let directory = directories.joined(separator: "/")
            if isPackage(directory) { return directory }
            directories.removeLast()
        }
        return nil
    }

    /// `literal` resolved from the root-relative `directory`, standardised (`.` and `..` folded over
    /// the whole absolute path, lexically, as SwiftPM folds them), then resolved through symlinks
    /// (amendment H), as a root-relative path without a trailing `/`; `nil` when the result is not
    /// under the root. `rootPath` went through the same `resolvingSymlinks`, so a `/private/tmp/…`
    /// literal under a `/tmp/…` root, a dependency reached through a symlinked directory, and one
    /// spelled in another letter case each name the directory the compiler opens.
    static func resolve(
        _ literal: String,
        from directory: String,
        rootPath: String,
        with resolvingSymlinks: (String) -> String = \.self
    ) -> String? {
        let root = rootPath.split(separator: "/").map(String.init)
        let base = literal.hasPrefix("/") ? [] : root + directory.split(separator: "/").map(String.init)
        guard let lexical = standardised(base + literal.split(separator: "/").map(String.init)) else { return nil }
        let absolute = resolvingSymlinks("/" + lexical.joined(separator: "/")).split(separator: "/").map(String.init)
        guard absolute.starts(with: root) else { return nil }
        return absolute.dropFirst(root.count).joined(separator: "/")
    }

    /// `components` with `.` dropped and `..` folded, or `nil` when `..` climbs above `/`.
    private static func standardised(_ components: [String]) -> [String]? {
        var result: [String] = []
        for component in components where component != "." {
            if component == ".." {
                guard !result.isEmpty else { return nil }
                result.removeLast()
            } else {
                result.append(component)
            }
        }
        return result
    }
}
