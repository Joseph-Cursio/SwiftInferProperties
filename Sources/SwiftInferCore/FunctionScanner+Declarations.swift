import Foundation
import SwiftParser

/// The declarations-only scan: what a directory declares, with no purity question asked.
///
/// `scanCorpus(directory:)` is two-phase since construction facts were wired in — it parses the
/// project's whole construction universe and builds SEI's table before judging a file — and that is
/// what a caller reading VERDICTS needs. A caller reading only `typeDecls` pays all of it for
/// nothing: measured on `index --target Tiny --scan-dependencies --dry-run` (one-file package, this
/// repo's 11 checkouts), 3.2–3.4 s user and 73–76 MB peak RSS on main against 4.5 s and 408–411 MB
/// once each dependency scan built its universe — with byte-identical output.
///
/// So this parses each file of `directory` alone, one at a time, keeps no tree, and builds no
/// table. Every summary the walk makes is judged by the unconfigured oracle and thrown away
/// unread; **no verdict leaves this function**, which is why it alone in production may name
/// `SoundPurity.unconfigured` (`PurityConfigurationInventoryTests` allow-lists this file).
extension FunctionScanner {

    /// The `typeDecls` `scanCorpus(directory:)` would return for `directory` — byte-identical,
    /// `PreconditionHelperHop` applied per file and then across the directory, as the package-scope
    /// merge does — without the construction universe, the table, or the join.
    ///
    /// Throws when a file cannot be read as UTF-8, as the full scan does. The serial loop runs on
    /// one `LargeStackWorkers` thread: a parse recurses as deep as its source nests, and a CLI
    /// command's cooperative thread has ~512 KB.
    public static func scanTypeDecls(directory: URL) throws -> [TypeDecl] {
        let files = SwiftSourceFiles.sorted(in: directory)
        guard !files.isEmpty else { return [] }
        let scanned: Result<Declarations, any Error> = LargeStackWorkers.run {
            Result {
                var declarations = Declarations()
                for file in files {
                    let source = try String(contentsOf: file, encoding: .utf8)
                    let corpus = scanCorpus(tree: Parser.parse(source: source), file: file.path, purity: .unconfigured)
                    declarations.typeDecls.append(contentsOf: corpus.typeDecls)
                    declarations.trapping.formUnion(corpus.trappingFunctions)
                }
                return declarations
            }
        }
        let declarations = try scanned.get()
        return PreconditionHelperHop.applied(to: declarations.typeDecls, trapping: declarations.trapping)
    }

    /// What the declarations-only loop keeps per directory.
    private struct Declarations: Sendable {
        var typeDecls: [TypeDecl] = []
        var trapping: Set<String> = []
    }
}
