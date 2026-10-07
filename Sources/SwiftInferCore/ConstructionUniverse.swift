import Foundation

/// Which files a scan's `ConstructionFacts` are built from — the production sources of the
/// project the scan belongs to, not the directory the scan was handed.
///
/// SEI's `ConstructionFacts.build(from:)` asks for production sources only, in a fixed order, and
/// can check neither: it takes trees, not paths. So the rule lives in the consumer. **It is the
/// SAME rule SwiftProjectLint applies, with the same names**, and agreement is not a matter of
/// prose: both repos carry a byte-identical `construction-universe.tsv` (the predicate's answer key)
/// and `construction-universe-cases.json` (the manifest reader's and the order's), each asserts its
/// own implementation over every row (`ConstructionUniverseTests`), and `SEICrossRepoPinTests`
/// asserts both pairs of files are identical. An equal SEI pin is necessary for the two consumers
/// to consult one oracle and no longer sufficient: the table each builds depends on its universe,
/// so the universes must be equal too.
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
/// names, `*Test.swift` and `*Tests.swift` *file* names (a production `ABTest.swift`), the nested
/// local packages the root compiles, and generated files. Keeping something that is not linked
/// can only add a namesake, which over-refutes — the direction SEI's "any doubt refutes" accepts.
///
/// ## The root — `root(forScanOf:)`
///
/// The nearest ancestor-or-self of the scanned directory holding a manifest — a `Package.swift`
/// whose first line is a tools-version comment (amendment F, `ConstructionUniverse+Manifests.swift`;
/// a source file of that name, a directory or a dangling link is not one) — **found from
/// the path as given** (standardised, symlinks NOT resolved), and only then resolved — resolved
/// paths are keys, never what decides the package. `--target Foo` scans `Sources/Foo`, but `Foo`
/// constructs types its sibling targets declare, and a per-target table misses them — the unsound
/// direction again. A `Sources/Foo` that is a symlink is still a target of the package holding the
/// link, so it is judged there, with that package's real sibling targets. Only when no ancestor of
/// the path as given holds a manifest is the walk retried from the resolved path, so a link from
/// outside every package into one still finds it.
///
/// **Except a scan under a component the predicate rejects is self-contained**: a test, fixture or
/// build directory is its own project. Walking up from `Tests/Fixtures/X` would reach this repo's
/// root, whose rule drops the fixture's own files — so the fixture's types would never reach its
/// table, and every such scan would parse the whole package for nothing.
///
/// **And no ancestor with a manifest means the scanned directory is its own root** — an Xcode app's
/// folder, or a workspace folder of packages. Every nested package below it is in (see below), so a
/// folder holding five unrelated packages builds ONE table from all of them. At SEI `9d0bf6d` that
/// build was superlinear — `ConstructionFacts.build` re-walked the member-type graph per decode site
/// and per fixpoint pass — and on swift-collections, swift-nio, swift-argument-parser,
/// swift-algorithms and swift-syntax side by side it cost ~14× the five packages scanned one by one,
/// or overflowed the stack. SEI #24 (`64a905c`) memoises it: the same folder (1,553 files) builds in
/// 16 s and 744 MB against 7.5 s summed. Partitioning per nested package here would drop the
/// constructions an app makes from its own local packages — the under-refuting direction — so it
/// is not done.
///
/// `--target`, `--sources` and a config's `excluded_paths` decide what is JUDGED, never what feeds
/// the table.
///
/// ## The universe — `universe(forScanOf:)`
///
/// The production files under the root, each classified by its root-relative path **where the walk
/// reached it** — for a symlinked file, where the link is, since that is where the compiler sees it —
/// **unioned** with the scanned directory's own production files, spelled the same way: the scanned
/// directory's path below the root (as given) plus each file's path below it. The walk never
/// descends a symlinked directory (nor does SwiftProjectLint's), so the union is what puts a scanned
/// symlinked `Sources/<target>` into its package's universe, under the link's spelling.
///
/// Then, in this order — the shared spec's first amendment, implemented identically in
/// SwiftProjectLint:
///
/// 1. **Bound by what the root compiles** (amendment B): a file inside a nested package is in only
///    when the root reaches that package through local path dependencies, or the root has no
///    manifest to say (`ConstructionUniverse+NestedPackages.swift`).
/// 2. **One entry per file on disk** (amendment A): entries whose resolved paths are one file are
///    collapsed to the one with the **smallest** relative path under `String <` — a rule on the
///    paths, never the walk's directory-listing order.
/// 3. **Strict UTF-8** (amendment C) is applied where the files are read: `PackagePurity` skips a
///    member `String(contentsOf:encoding: .utf8)` cannot decode, as no compiler reads one either.
///
/// **Order: `buildOrder(_:)` — root-relative path, Swift `String <`.** Not order-free — which
/// witness SEI reports first among several declarations of one name depends on input order (which
/// types refute does not, since SEI `9d0bf6d` follows every alias a name may mean) — so a fixed
/// order shared with SwiftProjectLint is what lets the two agree.
public enum ConstructionUniverse {

    /// Directory names never part of a universe even when not hidden: build products and vendored
    /// trees. Shared verbatim with SwiftProjectLint.
    public static let prunedDirectoryNames: Set<String> = ["DerivedData", "Pods", "Carthage", "node_modules"]

    /// One member of a universe.
    public struct Member: Sendable, Equatable {
        /// Root-relative, `/`-separated, where the walk reached the file — the sort key, and what
        /// the predicate judged.
        public let relativePath: String
        /// Where to read it from, as reached by the walk.
        public let url: URL
        /// The resolved absolute path — the dedup key, and how `PackagePurity` finds a tree.
        public let key: String
    }

    /// A scan's whole universe: the root, its members in build order, and the manifests whose text
    /// decided which nested packages are in.
    public struct Universe: Sendable {
        /// The root, resolved — one spelling per location.
        public let root: URL
        /// The production files, bounded and deduplicated, in `buildOrder`.
        public let members: [Member]
        /// The root's `Package.swift` when it has one, and every nested package's: an edit to any
        /// of them can move the bound, so whatever watches the members watches these too.
        public let manifests: [URL]
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

    /// The order the facts are built in: Swift `String <` over root-relative paths — the shared
    /// spec's order, asserted against `construction-universe-cases.json` in both repos. The one
    /// place the universe is sorted; `universe(forScanOf:)` orders its members through it.
    public static func buildOrder(_ relativePaths: [String]) -> [String] {
        relativePaths.sorted(by: <)
    }

    /// A directory component the predicate rejects — everything under it is out.
    static func isRejectedDirectory(_ name: String) -> Bool {
        isTestTargetDirectory(name) || name.hasPrefix(".") || prunedDirectoryNames.contains(name)
    }

    /// The root a scan of `directory` builds its table from — see the type's doc. One spelling
    /// per location: resolved, and rebuilt from its path, so a root reached as an ancestor
    /// (`…/pkg/`) and one reached as the scanned directory itself (`…/pkg`) compare equal.
    public static func root(forScanOf directory: URL) -> URL {
        RootLocation(forScanOf: directory).resolved
    }

    /// Every production file a scan of `directory` builds its table from, in the fixed order.
    public static func files(forScanOf directory: URL) -> [Member] {
        universe(forScanOf: directory).members
    }

    /// The scan's universe — see the type's doc for each step, in order.
    public static func universe(forScanOf directory: URL) -> Universe {
        let location = RootLocation(forScanOf: directory)
        let root = location.resolved
        let walk = walk(under: root)
        var members = walk.paths.map { relativePath in
            let url = root.appendingPathComponent(relativePath)
            return Member(relativePath: relativePath, url: url, key: resolved(url).path)
        }
        // The scanned directory's own production files, spelled under the root as given: the
        // scanned directory's path below it plus each file's path below the scanned directory.
        let prefix = location.scannedPathBelowRoot
        for url in SwiftSourceFiles.sorted(in: directory) {
            guard let own = relativePath(of: url, under: directory) else { continue }
            let relative = prefix.isEmpty ? own : prefix + "/" + own
            guard isProductionSource(relativePath: relative) else { continue }
            members.append(Member(relativePath: relative, url: url, key: resolved(url).path))
        }
        let rootHasManifest = holdsManifest(root)
        // An Xcode project beside the manifest may compile packages it never names (amendment G).
        let compiled = compiledNestedPackages(
            walk.nestedPackages,
            rootHasManifest: rootHasManifest && !holdsXcodeProject(root),
            rootPath: root.path,
            resolvingSymlinks: { resolved(URL(fileURLWithPath: $0)).path },
            packagesContaining: { packages(containing: $0, under: root) },
            manifests: { manifests(inDirectory: packageDirectory($0, under: root)) }
        )
        let bounded = members.filter { member in
            owningPackage(of: member.relativePath, among: walk.nestedPackages).map(compiled.contains) ?? true
        }
        // Every manifest that can move the bound — the closure's too, under `Tests/` or not.
        let manifests = (rootHasManifest ? [""] : []) + walk.nestedPackages.union(compiled).sorted()
        return Universe(
            root: root,
            members: ordered(deduplicated(bounded)),
            manifests: manifests.flatMap { manifestURLs(inDirectory: packageDirectory($0, under: root)) }
        )
    }

    /// One entry per file on disk: of the members whose `key` (resolved path) is one file, the one
    /// with the smallest `relativePath` under `String <` — whatever order they arrive in.
    static func deduplicated(_ members: [Member]) -> [Member] {
        var byKey: [String: Member] = [:]
        for member in members {
            if let kept = byKey[member.key], kept.relativePath < member.relativePath { continue }
            byKey[member.key] = member
        }
        return Array(byKey.values)
    }

    /// `members` in `buildOrder` of their relative paths. Two members never share a relative path
    /// (one location is one file); were they to, the smaller key goes first, so the order is still
    /// a function of the paths.
    static func ordered(_ members: [Member]) -> [Member] {
        var byPath: [String: [Member]] = [:]
        for member in members { byPath[member.relativePath, default: []].append(member) }
        return buildOrder(Array(byPath.keys)).flatMap { path in
            (byPath[path] ?? []).sorted { $0.key < $1.key }
        }
    }

    /// What the root walk found: the production files' root-relative paths, unsorted, and the
    /// root-relative directories below the root that hold a manifest (amendment F).
    struct Walk {
        var paths: [String] = []
        var nestedPackages: Set<String> = []
    }

    /// The production `.swift` files under `root`, and the nested packages among its directories.
    ///
    /// Pruned during the walk rather than filtered after it: the predicate rejects a path for a
    /// directory component, so nothing below a rejected directory can be kept, and this repo's
    /// `Tests/` alone is more files than its `Sources/`. Hidden entries are skipped the same way.
    /// Symlinked directories are not descended — the path enumerator does not follow them — and a
    /// symlinked FILE is yielded where the link is, which is where it is classified.
    static func walk(under root: URL) -> Walk {
        var result = Walk()
        guard let walker = FileManager.default.enumerator(atPath: root.path) else { return result }
        while let relative = walker.nextObject() as? String {
            let components = relative.split(separator: "/").map(String.init)
            let name = components.last ?? relative
            if walker.fileAttributes?[.type] as? FileAttributeType == .typeDirectory {
                if isRejectedDirectory(name) { walker.skipDescendants() }
                continue
            }
            // A nested package is a directory holding a MANIFEST (amendment F): a source file
            // that happens to be called `Package.swift`, or a dangling link, makes no boundary.
            if name == "Package.swift", components.count > 1 {
                let directory = components.dropLast().joined(separator: "/")
                if holdsManifest(root.appendingPathComponent(directory)) { result.nestedPackages.insert(directory) }
            }
            if !name.hasPrefix("."), isProductionSource(relativePath: relative) { result.paths.append(relative) }
        }
        return result
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

    /// The root-relative `directory` under `root`; `""` is the root itself.
    static func packageDirectory(_ directory: String, under root: URL) -> URL {
        directory.isEmpty ? root : root.appendingPathComponent(directory)
    }

    /// One spelling per location: standardized, every symlink resolved.
    static func resolved(_ url: URL) -> URL {
        url.standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Where a scan's root was found, and how the scanned directory is spelled below it.
    ///
    /// The walk up starts from the scanned directory **as given** — standardised, never resolved —
    /// so a symlinked `Sources/<target>` finds the package that holds the link. Only when that
    /// finds no manifest is it retried from the resolved path. The chosen root is then resolved:
    /// that spelling is the key, compared by `PackagePurity.covers`.
    struct RootLocation {
        /// The root, resolved and rebuilt from its path.
        let resolved: URL
        /// The scanned directory's components below the root, in the spelling the root was found
        /// in; empty when the scanned directory is its own root.
        let scannedPathBelowRoot: String

        init(forScanOf directory: URL) {
            let given = directory.standardizedFileURL
            for scanned in [given, ConstructionUniverse.resolved(directory)] {
                guard let package = DirectoryAncestors.nearest(from: scanned, where: holdsManifest) else { continue }
                let below = Array(scanned.pathComponents.dropFirst(package.pathComponents.count))
                let selfContained = below.contains(where: isRejectedDirectory)
                let root = selfContained ? scanned : package
                self.resolved = URL(fileURLWithPath: ConstructionUniverse.resolved(root).path)
                self.scannedPathBelowRoot = selfContained ? "" : below.joined(separator: "/")
                return
            }
            self.resolved = URL(fileURLWithPath: ConstructionUniverse.resolved(directory).path)
            self.scannedPathBelowRoot = ""
        }
    }
}
