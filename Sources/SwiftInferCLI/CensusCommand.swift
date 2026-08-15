import ArgumentParser
import Foundation
import SwiftInferCore

extension SwiftInferCommand {

    /// Count rows per template across several registered corpora, recording **which corpora**
    /// as part of the run.
    ///
    /// ## Why this is a command and not a shell loop
    ///
    /// It was a shell loop, and the loop is what went wrong. A census concludes things of the
    /// form *"6 of 39 templates never fire"*, which is a claim about a corpus list — and the
    /// list lived in prose written afterwards. Twice that prose turned out not to match the run:
    /// `involution` was called dead with a witness sitting in a ninth corpus already measured
    /// here, and four registry entries claimed membership in the eight-corpus sweep while only
    /// one was in it. Neither was a counting error. Both were denominator errors, and neither
    /// was visible from the numbers.
    ///
    /// So the denominator is now the first thing the artifact records, by registry id, together
    /// with the revision each checkout actually stood on and the flags the pipeline ran under.
    ///
    /// ## What it deliberately does NOT do
    ///
    /// **It does not print which templates never fired**, and that omission is the honest one.
    /// A zero is absence, and absence is not in the counts — naming it needs a catalog of every
    /// template that *could* have fired, and this project has no trustworthy runtime source for
    /// that: `TemplateName` is 18 cases against ~92 template files and `TemplatePack
    /// .allTemplateNames` is 10, and both reject tags that are correct. Printing a zero list
    /// against either would manufacture exactly the over-confident claim this command exists to
    /// prevent. `CensusRun.zeroRowTemplates(against:)` takes the catalog as an argument so the
    /// reader supplies what they mean, and the zero stays attached to the list that produced it.
    struct Census: AsyncParsableCommand {

        static let configuration = CommandConfiguration(
            commandName: "census",
            abstract: "Count rows per template across registered corpora, recording which ones.",
            discussion: """
            Surveys each corpus named by --corpus, resolving its tree and target out of \
            fixtures/corpora/manifest.json, and writes a run that records the corpus list by id \
            alongside the counts. A census conclusion is only as wide as its corpus list, and \
            this makes the list a fact of the run rather than prose written afterwards.

            It does not report which templates never fired: that needs a catalog of every \
            template that could have fired, and no trustworthy runtime source for one exists. \
            The counts are recorded so a reader can take that step against the catalog they mean.
            """
        )

        @Option(
            name: .customLong("corpus"),
            help: "Registry id to survey; repeat for several. See `swift-infer corpus`."
        )
        var corpora: [String] = []

        @Option(help: "What this census is for, in a line. Recorded verbatim.")
        var label: String = "catalog health census"

        @Option(help: "Write the run here as JSON. Omit to print the table only.")
        var out: String?

        @Flag(
            inversion: .prefixedNo,
            help: "Include below-cut conjectures. On by default: the standing census did."
        )
        var includePossible: Bool = true

        @Option(help: "Override the working directory (defaults to the current one).")
        var directory: String?

        func run() async throws {
            let root = URL(fileURLWithPath: directory ?? ".").standardizedFileURL
            // An empty corpus list would survey nothing and print a table of zeros, which reads
            // exactly like a catalog in which nothing fires. Refusing is the same rule
            // `--apparatus` already applies to a name that matches nothing.
            guard !corpora.isEmpty else { throw NoCorporaNamed(known: try knownIDs(root: root)) }

            let manifest = try CorpusManifest.load(repositoryRoot: root)
            var members: [CensusRun.Member] = []
            for id in corpora {
                guard let entry = manifest.entry(id: id) else {
                    throw CorpusRunPlan.ResolveError.unknownCorpus(
                        id: id, known: manifest.identifiers
                    )
                }
                members.append(try survey(entry: entry, root: root))
            }

            let run = CensusRun(
                schemaVersion: CensusRun.currentSchemaVersion,
                label: label,
                capturedAt: Date(),
                flags: includePossible ? "--include-possible" : "(default tier)",
                swiftInferVersion: BuildIdentity.versionString("1.149.0"),
                corpora: members
            )

            if let out {
                let url = URL(fileURLWithPath: out)
                try CensusRun.write(run, to: url)
            }
            print(CensusRenderer.render(run, wroteTo: out), terminator: "")
        }

        private func knownIDs(root: URL) throws -> [String] {
            try CorpusManifest.load(repositoryRoot: root).identifiers
        }

        /// A census scans a DIRECTORY; `prove-then-show` builds a TARGET. That is why this
        /// resolves the scan path itself instead of reusing `CorpusRunPlan`.
        ///
        /// `CorpusRunPlan` resolves `Sources/<target>` unconditionally, which is right for a
        /// survey that has to compile the thing. A census only reads source, so it can reach
        /// code no SwiftPM target names — and the original sweep did exactly that, running
        /// `discover --sources <path>`. `swiftlang-swift` is the witness: the compiler repo has
        /// no `Sources/` directory at all and its stdlib sits at `stdlib/public/core`, three
        /// levels down. Routing a census through the target resolver put it at `Sources/stdlib`,
        /// which does not exist, and the failure surfaced as *"the file couldn't be opened
        /// because it isn't in the correct format"* — a decode error, from a path.
        ///
        /// So `sources` wins when the entry has one, and the resolved path is checked to exist
        /// before scanning. **An absent directory must refuse, not scan.** A census over a
        /// missing path reports zero rows for every template, which is the exact shape of
        /// *every template is dead* — the conclusion this command exists to keep honest.
        private func survey(entry: CorpusManifest.Entry, root: URL) throws -> CensusRun.Member {
            let scanPath = try Self.scanPath(for: entry, root: root)

            let status = CorpusStatus.resolve(entry, repositoryRoot: root)
            for warning in Self.warnings(for: status) {
                FileHandle.standardError.write(Data(("warning: " + warning + "\n").utf8))
            }

            let result = try Discover.collectVisibleSuggestions(
                directory: scanPath,
                includePossible: includePossible,
                diagnostics: SilentDiagnostics()
            )
            var rows: [String: Int] = [:]
            for suggestion in result.suggestions { rows[suggestion.templateName, default: 0] += 1 }

            // A corpus contributing nothing is legitimate and is also what a misconfigured scan
            // path looks like, so it is said rather than left to be noticed. `swift-collections`
            // is why: its `Collections` target is a pure re-export umbrella with zero
            // declarations, so the census scanned real files and found no API, and reported
            // `0 rows` next to corpora reporting four figures. That was caught by eye, in a
            // table, once — which is not a mechanism.
            //
            // A WARNING and not a refusal: zero rows over a real corpus is a true answer, and
            // refusing would make the tool unable to report the finding a census exists to
            // find. What is not acceptable is zero passing silently.
            if rows.isEmpty {
                FileHandle.standardError.write(Data(("""
                warning: corpus '\(entry.id)' contributed 0 rows from \(scanPath.path) — \
                legitimate if the subject genuinely offers no laws, but this is also what an \
                umbrella target or a wrong scan path looks like. Check that path holds \
                declarations before reading this census.

                """).utf8))
            }

            var revision: String?
            var dirty = false
            if case let .resolved(_, head, isDirty) = status.checkout {
                revision = head
                dirty = isDirty
            }
            return CensusRun.Member(
                id: entry.id,
                revision: revision,
                dirty: dirty,
                pin: status.pin.token,
                rowsByTemplate: rows
            )
        }

        /// Where a census READS, which is not always where `prove-then-show` BUILDS.
        ///
        /// `sources` wins when present, because it answers this question directly; `target` is
        /// the fallback and means the conventional `Sources/<target>`. Both may be set, and on
        /// `swift-collections` they must be: `Collections` is the buildable target and a pure
        /// re-export umbrella, so scanning it finds zero declarations.
        private static func scanPath(for entry: CorpusManifest.Entry, root: URL) throws -> URL {
            let tree = entry.resolvedPath(repositoryRoot: root)
            let path: URL
            if let sources = entry.sources {
                path = tree.appendingPathComponent(sources)
            } else if let target = entry.target {
                path = tree.appendingPathComponent("Sources").appendingPathComponent(target)
            } else {
                throw UnscannableCorpus(
                    id: entry.id, reason: "it names neither sources nor a target"
                )
            }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: path.path, isDirectory: &isDirectory
            )
            guard exists, isDirectory.boolValue else {
                throw UnscannableCorpus(
                    id: entry.id,
                    reason: "its scan path '\(path.path)' is not a directory. Set `sources` on "
                        + "the entry if this subject's code is not under Sources/<target>"
                )
            }
            return path
        }

        /// Said on stderr as well as stored, because a caveat only in the artifact is one the
        /// person watching the run does not see.
        private static func warnings(for status: CorpusStatus) -> [String] {
            var warnings: [String] = []
            if case let .resolved(_, _, dirty) = status.checkout, dirty {
                warnings.append(
                    "corpus '\(status.entry.id)' has a DIRTY tree — its rows count uncommitted "
                        + "work and its recorded revision does not fully name what was surveyed"
                )
            }
            if case let .movedOff(head, pinned, _) = status.pin {
                warnings.append(
                    "corpus '\(status.entry.id)' is at \(String(head.prefix(7))) but its baseline "
                        + "was measured at \(String(pinned.prefix(7))) — recorded, not refused"
                )
            }
            return warnings
        }
    }
}

/// Refusing an empty run rather than reporting one.
///
/// Top-level rather than nested: `Census` is already one level inside `SwiftInferCommand`, and a
/// third trips `nesting` — the same reason `ResolvedSurvey` sits beside `CorpusRunPlan`.
struct NoCorporaNamed: Error, CustomStringConvertible {
    let known: [String]
    var description: String {
        "swift-infer census: name at least one corpus with --corpus. A census over zero corpora "
            + "prints a table of zeros, which is indistinguishable from a catalog in which "
            + "nothing fires. Known ids: " + known.joined(separator: ", ")
    }
}

/// Refusing a corpus whose code cannot be located, rather than reporting it as empty.
struct UnscannableCorpus: Error, CustomStringConvertible {
    let id: String
    let reason: String
    var description: String {
        "swift-infer census: cannot scan corpus '\(id)' — \(reason). Refused rather than "
            + "surveyed: a census over a path that is not there returns zero rows for every "
            + "template, which is indistinguishable from a catalog in which nothing fires."
    }
}
