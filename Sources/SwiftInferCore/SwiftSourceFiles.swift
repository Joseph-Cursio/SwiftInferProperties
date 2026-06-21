import Foundation

/// Shared `.swift`-file directory enumeration for every discoverer that scans
/// a target directory (`FunctionScanner`, `ViewModelDiscoverer`,
/// `ReducerDiscoverer`, `RuleVisitorDiscoverer`, `ViewModelProtocolScanner`,
/// `SkipMarkerScanner`, …). Centralized so the symlinked-root fix lives in ONE
/// place — previously each discoverer re-implemented the same enumerate-then-
/// sort block, and a fix applied to only `FunctionScanner` (commit 5b0c4c9)
/// left the M2 discoverers still blind to a symlinked `Sources/<target>`
/// (surfaced by the Mastermind dogfood: `discover` saw the files but
/// `discover-reducers` reported zero carriers).
public enum SwiftSourceFiles {

    /// Recursively enumerate every `.swift` file under `directory`, returned in
    /// deterministic sorted-path order (supports the byte-identical-repro
    /// guarantee, PRD v0.3 §16 #6). Returns `[]` when the directory can't be
    /// enumerated.
    ///
    /// Resolves the root when its leaf is a symlink, because
    /// `FileManager.enumerator(at:)` yields ZERO entries — with no error — for
    /// a root URL that is itself a symlink to a directory. Resolution is gated
    /// on the leaf being a symlink so normal real-dir scans keep their exact
    /// paths (`resolvingSymlinksInPath` would otherwise canonicalize e.g.
    /// `/tmp` → `/private/tmp`).
    public static func sorted(in directory: URL) -> [URL] {
        let root = isSymbolicLink(directory)
            ? directory.resolvingSymlinksInPath()
            : directory
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            files.append(url)
        }
        files.sort { $0.path < $1.path }
        return files
    }

    /// Whether `url`'s leaf is a symbolic link (vs. a real directory/file).
    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
    }
}
