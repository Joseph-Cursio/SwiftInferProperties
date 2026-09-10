import Foundation

/// The chain of directories from one directory up to the root it belongs to.
///
/// Six copies of this walk lived in `SwiftInferCLI` as `findPackageRoot(startingFrom:)` and
/// `walkUpForPackageManifest(startingFrom:)`, and a seventh in
/// `KitEvidenceStore.packageRoot(startingFrom:)`. Three of them carried a comment saying they were
/// inlined on purpose, *"because each loader's posture is to stay independent"* — which is a
/// statement about API coupling and was never the problem. The problem was that the only total
/// function in the walk had no name, so **not one of the seven could be tested**: each mixed a pure
/// ancestor chain with a `FileManager.fileExists` probe, and reaching the chain meant having a real
/// directory tree.
///
/// Separating them leaves the effect at the call site and the arithmetic here:
///
/// ```swift
/// DirectoryAncestors.chain(from: directory).first { candidate in
///     fileManager.fileExists(atPath: candidate.appendingPathComponent("Package.swift").path)
/// }
/// ```
///
/// ## The defect naming it found
///
/// Every copy was `while true`, stopping only when `deletingLastPathComponent()` reached a
/// fixpoint. **For a relative URL with no scheme that never happens.** `URL(string: "foo")`,
/// `URL(string: "a/b")` and `URL(string: ".")` each grow under `deletingLastPathComponent()` —
/// `foo`, `../`, `../../`, without end — so all seven copies looped forever on one. Measured before
/// this was written: 500 iterations with no fixpoint, the path still lengthening.
///
/// The repair is the invariant the loop always assumed and never checked: **walking up shortens the
/// path.** A parent with no fewer path components than its child is not an ancestor, and the chain
/// ends there. That makes the function total for every `URL`, which is what lets a law quantify
/// over one.
public enum DirectoryAncestors {

    /// `directory` standardized, then each proper ancestor in turn, ending at the root.
    ///
    /// Never empty: the first element is always `directory.standardizedFileURL`, so a caller
    /// searching the chain always considers the directory it asked about.
    public static func chain(from directory: URL) -> [URL] {
        var result = [directory.standardizedFileURL]
        while true {
            let current = result[result.count - 1]
            let parent = current.deletingLastPathComponent().standardizedFileURL
            // Two ways to stop, and the second is the one that makes this total. A fixpoint is the
            // ordinary end of an absolute path (`/` is its own parent). A parent that is not
            // shorter is a relative URL growing `../` prefixes, where there is no root to reach.
            guard parent != current,
                  parent.pathComponents.count < current.pathComponents.count else { return result }
            result.append(parent)
        }
    }

    /// The nearest directory in the chain that satisfies `predicate`, or `nil`.
    ///
    /// The shape every caller wanted. `predicate` is where the file system goes, so it is the only
    /// impure part and it is supplied by the caller.
    public static func nearest(
        from directory: URL,
        where predicate: (URL) -> Bool
    ) -> URL? {
        chain(from: directory).first(where: predicate)
    }
}
