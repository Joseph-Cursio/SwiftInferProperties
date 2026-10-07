import Foundation

/// The nested-package bound of one scan: which packages its judged files belong to (amendment J),
/// and the shared closure (`ConstructionUniverse+NestedPackages.swift`) run over them on a large
/// stack (amendment K), comparing every location by its canonical path (amendments H and Q).
extension ConstructionUniverse {

    /// The nested packages of `nestedPackages` the bound takes — `compiledNestedPackages`, the
    /// shared closure — and the nested directories it read, which decide it.
    ///
    /// The closure runs on a `LargeStackWorkers` thread (amendment K): it parses every manifest it
    /// reaches, a parse recurses as deep as the manifest nests, and the CLI runs on a ~512 KB
    /// cooperative stack — a 1,000-arm `else if` in a nested manifest `SIGBUS`ed `discover`.
    /// SwiftProjectLint runs its closure on a large stack at its call site too, so the shared body
    /// stays the same in both repos.
    static func bound(
        of nestedPackages: Set<String>,
        judging directory: URL,
        at location: RootLocation,
        rootHasManifest: Bool
    ) -> (compiled: Set<String>, read: Set<String>) {
        let root = location.resolved
        // An Xcode project beside the manifest may compile packages it never names (amendment G).
        let bounds = rootHasManifest && !holdsXcodeProject(root)
        let judged = bounds && !nestedPackages.isEmpty
            ? judgedPackages(of: judgedFiles(of: directory, at: location).map(\.relativePath), among: nestedPackages)
            : []
        return LargeStackWorkers.run {
            var read: Set<String> = []
            let compiled = compiledNestedPackages(
                nestedPackages,
                reported: judged,
                rootHasManifest: bounds,
                rootPath: root.path,
                resolvingSymlinks: canonicalPath
            ) { relative in
                let manifests = manifests(inDirectory: packageDirectory(relative, under: root))
                if !relative.isEmpty, manifests.contains(where: { $0 != .absent }) { read.insert(relative) }
                return manifests
            }
            return (compiled, read)
        }
    }

    /// An absolute path's canonical form — symlinks resolved and, on a volume that folds case, the
    /// on-disk letter case, as `realpath(3)` gives it — or the path itself when it does not resolve.
    /// The closure compares every location this way (amendments H and Q), as SwiftProjectLint does.
    static func canonicalPath(_ path: String) -> String {
        guard let canonical = realpath(path, nil) else { return path }
        defer { free(canonical) }
        return String(cString: canonical)
    }

    /// Every file a scan of `directory` judges, spelled under the root as given, as
    /// `ownMembers(of:at:)` spells its own: they say which nested packages the scan judges
    /// (amendment J).
    static func judgedFiles(of directory: URL, at location: RootLocation) -> [Member] {
        let prefix = location.scannedPathBelowRoot
        return SwiftSourceFiles.sorted(in: directory).compactMap { url in
            guard let own = relativePath(of: url, under: directory) else { return nil }
            let relative = prefix.isEmpty ? own : prefix + "/" + own
            return Member(relativePath: relative, url: url, key: resolved(url).path)
        }
    }

    /// The nested packages that hold a judged file — each file's nearest one of `nestedPackages`
    /// above it — the shared spec's amendment J, as SwiftProjectLint places its reported files.
    /// Placed by where the file is judged, like every member: a linked file belongs to the package
    /// its link sits in.
    static func judgedPackages(of relativePaths: [String], among nestedPackages: Set<String>) -> Set<String> {
        Set(relativePaths.compactMap { owningPackage(of: $0, among: nestedPackages) })
    }
}
