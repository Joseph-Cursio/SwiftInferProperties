import Foundation

/// Which files a scan's `ConstructionFacts` are built from — the production sources of the
/// project the scan belongs to, not the directory the scan was handed.
///
/// SEI's `ConstructionFacts.build(from:)` asks for production sources only, in a fixed order, and
/// can check neither: it takes trees, not paths. So the rule lives in the consumer. **It is the
/// SAME rule SwiftProjectLint applies, with the same names**, and agreement is not a matter of
/// prose: both repos carry a byte-identical `construction-universe.tsv` (ours at
/// `docs/construction-universe.tsv`), each asserts its predicate over every row
/// (`ConstructionUniverseTests`), and `SEICrossRepoPinTests` asserts the two files are identical.
/// An equal SEI pin is necessary for the two consumers to consult one oracle and no longer
/// sufficient: the table each builds depends on its universe, so the universes must be equal too.
///
/// ## The predicate — `isProductionSource(relativePath:)`
///
/// A root-relative, `/`-separated path is production unless its leaf is not a `.swift` file, the
/// leaf is a manifest (`Package.swift`, `Package@swift-*`), or a **directory** component is a test
/// target (`Tests`, `*Tests`), hidden (`.build`, `.git`, `.swiftpm`), or a vendored/build tree
/// (`prunedDirectoryNames`).
///
/// Deliberately **not** excluded, because dropping a compiled production type under-refutes —
/// the unsound direction: `TestSupport` / `Mock` / `Stub` / `Fake` / `Fixtures` / `Examples`
/// names, `*Test.swift` and `*Tests.swift` *file* names (a production `ABTest.swift`), nested local
/// packages, and generated files. Keeping something that is not linked can only add a namesake,
/// which over-refutes — the direction SEI's "any doubt refutes" accepts.
///
/// ## The root — `root(forScanOf:)`
///
/// The nearest ancestor-or-self of the scanned directory, symlinks resolved, holding a
/// `Package.swift`. `--target Foo` scans `Sources/Foo`, but `Foo` constructs types its sibling
/// targets declare, and a per-target table misses them — the unsound direction again.
///
/// **Except a scan under a component the predicate rejects is self-contained**: a test, fixture or
/// build directory is its own project. Walking up from `Tests/Fixtures/X` would reach this repo's
/// root, whose rule drops the fixture's own files — so the fixture's types would never reach its
/// table, and every such scan would parse the whole package for nothing.
///
/// `--target`, `--sources` and a config's `excluded_paths` decide what is JUDGED, never what feeds
/// the table.
///
/// ## The universe — `files(forScanOf:)`
///
/// The production files under the root, each judged by its root-relative path, **unioned** with
/// the scanned directory's own production files (judged by their path relative to it), deduplicated
/// by resolved path. The union is a safety net for what the root walk cannot reach: the enumerator
/// never descends a symlinked directory, and a symlinked `Sources/<target>` is a layout this tool
/// meets in real use (`SwiftSourceFiles`).
///
/// **Order: root-relative path, Swift `String <`.** Not order-free — SEI's alias resolution takes
/// the first target, and which witness is reported first depends on input order — so a fixed order
/// shared with SwiftProjectLint is what lets the two agree.
public enum ConstructionUniverse {

    /// Directory names never part of a universe even when not hidden: build products and vendored
    /// trees. Shared verbatim with SwiftProjectLint.
    public static let prunedDirectoryNames: Set<String> = ["DerivedData", "Pods", "Carthage", "node_modules"]

    /// One member of a universe.
    public struct Member: Sendable, Equatable {
        /// Root-relative, `/`-separated — the sort key, and what the predicate judged.
        public let relativePath: String
        /// Where to read it from, as reached by the walk.
        public let url: URL
        /// The resolved absolute path — the dedup key, and how `PackagePurity` finds a tree.
        public let key: String
    }

    /// Whether a directory name is a test target's: `Tests`, or any name ending in `Tests`.
    public static func isTestTargetDirectory(_ name: String) -> Bool {
        name == "Tests" || name.hasSuffix("Tests")
    }

    /// Whether `relativePath` — relative to the universe root, `/`-separated, never absolute — is
    /// production source. The rule is the type's doc; this is it verbatim.
    public static func isProductionSource(relativePath: String) -> Bool {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let leaf = components.last, leaf.hasSuffix(".swift") else { return false }
        if leaf == "Package.swift" || leaf.hasPrefix("Package@swift-") { return false }
        return !components.dropLast().contains(where: isRejectedDirectory)
    }

    /// A directory component the predicate rejects — everything under it is out.
    static func isRejectedDirectory(_ name: String) -> Bool {
        isTestTargetDirectory(name) || name.hasPrefix(".") || prunedDirectoryNames.contains(name)
    }

    /// The root a scan of `directory` builds its table from — see the type's doc. One spelling
    /// per location: resolved, and rebuilt from its path, so a root reached as an ancestor
    /// (`…/pkg/`) and one reached as the scanned directory itself (`…/pkg`) compare equal.
    public static func root(forScanOf directory: URL) -> URL {
        let scanned = resolved(directory)
        guard let package = DirectoryAncestors.nearest(from: scanned, where: hasManifest) else {
            return URL(fileURLWithPath: scanned.path)
        }
        let below = Array(scanned.pathComponents.dropFirst(package.pathComponents.count))
        return URL(fileURLWithPath: (below.contains(where: isRejectedDirectory) ? scanned : package).path)
    }

    /// Every production file a scan of `directory` builds its table from, in the fixed order.
    public static func files(forScanOf directory: URL) -> [Member] {
        let root = root(forScanOf: directory)
        var members: [Member] = []
        var seen: Set<String> = []
        for relativePath in productionPaths(under: root) {
            let url = root.appendingPathComponent(relativePath)
            let key = resolved(url).path
            if seen.insert(key).inserted {
                members.append(Member(relativePath: relativePath, url: url, key: key))
            }
        }
        // The scanned directory's own production files, judged relative to it. Under the root by
        // construction, so its root-relative spelling is the scanned directory's prefix plus its
        // own relative path — which is what keeps the sort a single order.
        let scanned = resolved(directory)
        let prefix = scanned.pathComponents.dropFirst(root.pathComponents.count).joined(separator: "/")
        for url in SwiftSourceFiles.sorted(in: directory) {
            guard let own = relativePath(of: url, under: directory),
                  isProductionSource(relativePath: own) else { continue }
            let key = resolved(url).path
            guard seen.insert(key).inserted else { continue }
            let relative = prefix.isEmpty ? own : prefix + "/" + own
            members.append(Member(relativePath: relative, url: url, key: key))
        }
        return members.sorted { lhs, rhs in
            lhs.relativePath == rhs.relativePath ? lhs.key < rhs.key : lhs.relativePath < rhs.relativePath
        }
    }

    /// Root-relative paths of every production `.swift` file under `root`, unsorted.
    ///
    /// Pruned during the walk rather than filtered after it: the predicate rejects a path for a
    /// directory component, so nothing below a rejected directory can be kept, and this repo's
    /// `Tests/` alone is more files than its `Sources/`. Hidden entries are skipped the same way.
    /// Symlinked directories are not descended — the path enumerator does not follow them.
    static func productionPaths(under root: URL) -> [String] {
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var paths: [String] = []
        while let relative = walker.nextObject() as? String {
            let name = relative.split(separator: "/").last.map(String.init) ?? relative
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if isRejectedDirectory(name) { walker.skipDescendants() }
                continue
            }
            if !name.hasPrefix("."), isProductionSource(relativePath: relative) { paths.append(relative) }
        }
        return paths
    }

    /// `url`'s path below `directory`, tolerating the enumerator's `/private/var` spelling of a
    /// root given as `/var` by trying both the standardized and the resolved prefix.
    static func relativePath(of url: URL, under directory: URL) -> String? {
        let path = url.standardizedFileURL.path
        for base in [directory.standardizedFileURL.path, resolved(directory).path] {
            let prefix = base.hasSuffix("/") ? base : base + "/"
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        let resolvedPath = resolved(url).path
        let prefix = resolved(directory).path + "/"
        return resolvedPath.hasPrefix(prefix) ? String(resolvedPath.dropFirst(prefix.count)) : nil
    }

    /// One spelling per location: standardized, every symlink resolved.
    static func resolved(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    private static func hasManifest(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent("Package.swift").path)
    }
}
