import Foundation

/// Where a scan's root is, and how the scanned directory is spelled below it — the shared spec's
/// amendments D (the root is found from the path as given) and L (in its on-disk letter case).
extension ConstructionUniverse {

    /// Where a scan's root was found, and how the scanned directory is spelled below it.
    ///
    /// The walk up starts from the scanned directory **as given** — standardised, never resolved —
    /// so a symlinked `Sources/<target>` finds the package that holds the link. Only when that
    /// finds no manifest is it retried from the resolved path. The chosen root is then resolved:
    /// that spelling is the key, compared by `PackagePurity.covers`.
    ///
    /// **As given, but in its on-disk letter case** (amendment L): `onDiskSpelling(of:)` first.
    /// On a volume that folds case, `--sources Tests/X` opens `tests/X`, and the predicate reads
    /// names — a `Tests` it rejects and a `tests` it does not. Spelled as typed, the rule became
    /// case-sensitive on a case-insensitive volume, both ways: a mis-cased `Tests` made a
    /// production `tests/X` self-contained (its package's `Item` left the table, `make` read
    /// pure), and a mis-cased `tests/fixtures/x` joined a fixture to the package (a namesake
    /// refuted it). And every member below a mis-cased `Sources/APP` was spelled `APP`, which moved
    /// the build order and SEI's first witness. SwiftProjectLint's walk yields on-disk names
    /// already, so only this side needed it.
    struct RootLocation {
        /// The root, resolved and rebuilt from its path.
        let resolved: URL
        /// The scanned directory's components below the root, in their on-disk spelling; empty
        /// when the scanned directory is its own root.
        let scannedPathBelowRoot: String

        init(forScanOf directory: URL) {
            let given = ConstructionUniverse.onDiskSpelling(of: directory.standardizedFileURL)
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

    /// `url`'s absolute path with each component in its on-disk spelling, symlinks NOT followed
    /// (a link keeps its own name): the name the file system stores for the entry the component
    /// opens — the exact name, or on a volume that folds case the one name it folds to — else,
    /// when the component opens nothing, the one case-insensitive match in its parent's listing,
    /// else the component as given.
    ///
    /// The stored name is read with `URLResourceKey.nameKey`, one `getattrlist` per component,
    /// rather than by listing every parent: a parent such as `$TMPDIR`, with ~12,000 entries here,
    /// cost 32 ms a listing, and a test suite asks for a root dozens of times.
    static func onDiskSpelling(of url: URL) -> URL {
        var current = URL(fileURLWithPath: "/")
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            let entry = current.appendingPathComponent(component)
            let name = (try? entry.resourceValues(forKeys: [.nameKey]))?.name ?? listedName(of: component, in: current)
            current = current.appendingPathComponent(name)
        }
        return current.standardizedFileURL
    }

    /// `component` matched against `directory`'s listing — for a component that opens nothing.
    static func listedName(of component: String, in directory: URL) -> String {
        onDiskName(of: component, among: (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    /// The entry of `names` that `component` names: the exact one, else the unique entry equal
    /// to it ignoring case, else `component` itself.
    static func onDiskName(of component: String, among names: [String]) -> String {
        if let exact = names.first(where: { $0 == component }) { return exact }
        let folded = names.filter { $0.compare(component, options: .caseInsensitive) == .orderedSame }
        return folded.count == 1 ? folded[0] : component
    }
}
