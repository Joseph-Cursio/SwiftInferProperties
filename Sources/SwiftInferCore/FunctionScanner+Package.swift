import Foundation
import SwiftParser
import SwiftSyntax

/// The package-scope entry points: a directory scan, which is two-phase, and the per-file scan
/// under a package's purity it is built from.
///
/// ## Two phases, and why the first is new
///
/// Every whole-package mechanism this scan had was a POST-pass over summaries —
/// `PackagePurityJoin`, `PreconditionHelperHop`, `TypeAliasMap`. `ConstructionFacts` is the first
/// PRE-pass: it is a fixpoint over every type in the project, so it has to exist before the first
/// function is judged. So a directory scan now parses its project's production universe first
/// (`PackagePurity.forScan(of:)`), builds the table once, and only then walks the files it was
/// asked about — judging each on the very tree the table was built from.
///
/// What is JUDGED is unchanged: `SwiftSourceFiles.sorted(in: directory)`. What feeds the table is
/// `ConstructionUniverse`, which is wider (a `--target` scan sees its sibling targets — the
/// package's own real targets, found from the path as given, so a symlinked target sees them too —
/// and the nested packages the root compiles) and stricter (a test file's namesake never refutes a
/// production constructor, and neither does a nested package the root never compiles).
///
/// A caller that reads only declarations — `typeDecls`, never a verdict — has no use for the first
/// phase and does not pay for it: `scanTypeDecls(directory:)`.
extension FunctionScanner {

    /// A purity was handed to a directory scan it was not built for.
    public enum ScanError: Error, Equatable, CustomStringConvertible {
        /// The value's root is not the root a scan of the directory would build its table from.
        case foreignPurity(scanned: String, root: String?)

        public var description: String {
            switch self {
            case let .foreignPurity(scanned, root):
                return "the purity handed to a scan of \(scanned) was built for "
                    + "\(root ?? "no project") — judging with another project's construction facts "
                    + "would answer for the wrong package"
            }
        }
    }

    /// Recursively scan every `.swift` file under `directory`. Files are
    /// visited in deterministic (sorted-path) order so the merged output
    /// is stable across runs.
    ///
    /// Judged under the purity of the project `directory` belongs to, built here — so every caller,
    /// the CLI and every measured arm alike, judges under the same table for the same directory.
    public static func scanCorpus(directory: URL) throws -> ScannedCorpus {
        // Nothing to judge, nothing to configure: an empty scan must not parse a whole package to
        // answer no question (`PackagePurity.forJudging(directory:)`).
        guard let purity = PackagePurity.forJudging(directory: directory) else { return merged([]) }
        return try merged(SwiftSourceFiles.sorted(in: directory).map { try scanCorpus(file: $0, purity: purity) })
    }

    /// The same scan under a purity the caller already built — once per project, however many of
    /// its directories are scanned. Cost only, never correctness: a value built for another
    /// project is rejected rather than used.
    public static func scanCorpus(directory: URL, purity: PackagePurity) throws -> ScannedCorpus {
        guard purity.covers(directory) else {
            throw ScanError.foreignPurity(scanned: directory.path, root: purity.root?.path)
        }
        let corpora = try SwiftSourceFiles.sorted(in: directory).map { try scanCorpus(file: $0, purity: purity) }
        return merged(corpora)
    }

    /// One file judged under a project's purity, unjoined like every per-file path. Reuses the
    /// project's tree when the file is in its universe, so the file is judged on the very nodes
    /// its facts were built from; a file outside it (a test file in a scan that reaches `Tests/`,
    /// a file of a nested package the root does not compile) is read and parsed here, and judged
    /// under the same table.
    ///
    /// That parse runs on a `LargeStackWorkers` thread, like the universe's: the CLI's commands run
    /// on a Swift-concurrency cooperative thread with ~512 KB of stack, and a parse recurses as deep
    /// as the source nests.
    public static func scanCorpus(file: URL, purity: PackagePurity) throws -> ScannedCorpus {
        if let tree = purity.tree(for: file) {
            return scanCorpus(tree: tree, file: file.path, purity: purity.oracle)
        }
        let source = try String(contentsOf: file, encoding: .utf8)
        let tree = LargeStackWorkers.run { Parser.parse(source: source) }
        return scanCorpus(tree: tree, file: file.path, purity: purity.oracle)
    }

    /// The package-scope merge of per-file corpora — the post-passes that need every
    /// declaration at once.
    static func merged(_ corpora: [ScannedCorpus]) -> ScannedCorpus {
        var summaries: [FunctionSummary] = []
        var identities: [IdentityCandidate] = []
        var typeDecls: [TypeDecl] = []
        var restricted: [RestrictedFunction] = []
        var aliases: [[String: String]] = []
        var trapping: Set<String> = []
        for corpus in corpora {
            summaries.append(contentsOf: corpus.summaries)
            identities.append(contentsOf: corpus.identities)
            typeDecls.append(contentsOf: corpus.typeDecls)
            restricted.append(contentsOf: corpus.restricted)
            aliases.append(corpus.typeAliases)
            trapping.formUnion(corpus.trappingFunctions)
        }
        return ScannedCorpus(
            // The one-hop refuting callee join, applied HERE and deliberately not in
            // `scanCorpus(source:file:)`. A single file is not a package: the join needs
            // every declaration's verdict before it can say a name is settled impure, and
            // running it per-file would let a name resolve against a fraction of its
            // declarations — the unanimity rule it depends on would be checked against
            // the wrong set. `PackagePurityJoin` carries the reasoning.
            summaries: PackagePurityJoin.applied(to: summaries),
            identities: identities,
            // Again at package scope: a helper in one file, an initializer in another (Harbeth).
            typeDecls: PreconditionHelperHop.applied(to: typeDecls, trapping: trapping),
            restricted: restricted,
            typeAliases: TypeAliasMap.merged(aliases),
            trappingFunctions: trapping
        )
    }
}
