import ArgumentParser
import Foundation

/// `swift-infer corpus` — print the measurement corpus and whether each checkout still stands
/// where its retained baseline was measured.
///
/// One command rather than a `list` / `check` pair: the registry is only ~20 lines of output
/// and the status is the reason anyone reads it, so splitting them would ship a subcommand
/// whose whole job is to withhold the interesting column. `--strict` is the CI gesture.
extension SwiftInferCommand {

    public struct Corpus: ParsableCommand {

        public static let configuration = CommandConfiguration(
            commandName: "corpus",
            abstract: "Show the subject codebases the toolchain is measured against, and "
                + "whether each checkout still stands at the revision its baseline was taken at."
        )

        @Option(name: .long, help: "Repository root holding \(CorpusManifest.relativePath).")
        public var directory: String?

        @Option(
            name: .long,
            help: """
            Show only corpora measured by one apparatus — prove-then-show, census, \
            kit-suite-backtest, swiftorg-study, road-test, planted-defect. This is the question \
            each of those used to answer from its own private list, which is why "the corpus" \
            meant something different depending on which tool you had run. An unknown name is \
            an error listing the known ones, not an empty report.
            """
        )
        public var apparatus: String?

        @Flag(
            name: .long,
            help: """
            Exit non-zero when a corpus has moved off its pin or its tree is dirty — either \
            makes a survey taken there incomparable with the retained baseline. A corpus that \
            could NOT be checked does not fail the gate, because a clone absent on this \
            machine is the ordinary case; it is reported, and the summary states how many of \
            how many were actually read.
            """
        )
        public var strict: Bool = false

        public init() { /* no-op */ }

        public func run() throws {
            let root = URL(fileURLWithPath: directory ?? ".").standardizedFileURL
            let manifest = try CorpusManifest.load(repositoryRoot: root)
            let selected = try select(from: manifest)
            let statuses = selected.map { CorpusStatus.resolve($0, repositoryRoot: root) }
            print(
                CorpusStatusRenderer.render(statuses, apparatus: apparatus), terminator: ""
            )
            guard strict else { return }
            // `--strict` fails on the states the person running it can fix BEFORE the sweep they
            // are about to start: check out the pin, or clean the tree. Everything else is
            // reported loudly and passes.
            //
            // `.revisionUnrecoverable` is the uncomfortable one and it deliberately does NOT
            // fail. It is a defect in the *record*, identical on every machine, and unfixable
            // by anything at gate time — the only remedy is re-running the measurement. Failing
            // on it would hold the gate red until someone re-runs a road test, and a gate that
            // is permanently red is one people route around, which costs the `.movedOff`
            // detection this exists for. The pressure to fix it lives in the summary line, which
            // names it in capitals and never folds it into `noBaseline`.
            let unsound = statuses.filter { status in
                switch status.pin {
                case .movedOff: return true
                case let .atPin(dirty): return dirty
                case .noBaseline, .uncheckable, .revisionUnrecoverable: return false
                }
            }
            guard unsound.isEmpty else {
                throw ExitCode(1)
            }
        }

        /// Apply `--apparatus`, rejecting a name no measurement uses.
        ///
        /// **A typo must not render as an empty corpus.** `--apparatus censsus` producing
        /// "0 corpora matched" reads as a coverage gap and would send someone to measure
        /// something that is already measured — so an unknown name is an error that lists the
        /// real ones, and only a genuinely unmeasured apparatus yields the empty report.
        private func select(from manifest: CorpusManifest) throws -> [CorpusManifest.Entry] {
            guard let apparatus else { return manifest.corpora }
            let known = manifest.apparatuses
            guard known.contains(apparatus) else {
                throw UnknownApparatus(name: apparatus, known: known)
            }
            return manifest.corpora(measuredBy: apparatus)
        }
    }

    /// Its own error rather than `VerifyError.invalidArguments`, which prefixes every message
    /// with `swift-infer verify:` — a `corpus` invocation reporting a verify error names the
    /// wrong command, and the first thing a reader does with a command name is re-run it.
    struct UnknownApparatus: Error, CustomStringConvertible {
        let name: String
        let known: [String]

        var description: String {
            "swift-infer corpus: no measurement in \(CorpusManifest.relativePath) names "
                + "apparatus '\(name)'. Known: \(known.joined(separator: ", "))."
        }
    }
}
