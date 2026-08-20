import Foundation
import Testing

/// Every `docs/…` path a **live doc** names in prose, checked against the files that
/// actually exist.
///
/// ## Why this exists on top of ``DocCitationTests``
///
/// That suite checks two populations: `docs/…` paths in Swift comments, and markdown
/// **link** syntax (`](…)`) between docs. A path written in *prose* — the
/// `` `docs/design/verify-edge-pass.md` `` backtick form this repo's docs use
/// constantly — is checked by neither, and that is not a corner: it is how docs cite
/// each other here almost everywhere.
///
/// The gap was measured on 2026-08-07, when the reorganisation that moved 64 docs into
/// `design/` `measurements/` `plans/` `reference/` left **130 unresolvable occurrences
/// over 60 distinct paths**. Both existing checks were green throughout. 72 of those
/// were pure directory moves — a class that is trivially detectable and had simply
/// never been looked for.
///
/// ## Live docs only, and the exclusions are the interesting part
///
/// A citation is a promise the target is reachable. A **history** file makes no such
/// promise: it records what was true when written, so a path that has since been
/// pruned is *correct* there and repointing it would be the actual error. Three files
/// are history and are out of scope wholesale:
///
/// - `docs/archive/` — the archived CLAUDE.md alone carries ~50 citations to per-cycle
///   findings docs pruned in `59bc93b`. (Its citations to docs that merely *moved*
///   were repointed on 2026-08-07; the pruned ones were deliberately left dangling.)
/// - `CHANGELOG.md` and `README.md` — per-release notes, ~280 citations to the pruned
///   perf baselines and calibration plans between them.
///
/// Excluding a whole file is a real cost: a *new* citation added to one of them is
/// unchecked. That is the trade, and it is taken knowingly, because the alternative is
/// an allowlist with ~330 entries that nobody would read.
///
/// ## Three exemptions inside the live set
///
/// 1. **`git show <sha>:docs/…`** — the repo's convention for a pruned doc, asserted in
///    the opposite direction by ``DocCitationTests/historicalCitationsNameRemovedDocs()``.
/// 2. **A bare mention accompanied on the same line by its own recovery pointer.** The
///    readable form is *"recorded in `docs/perf-baseline-v0.1.md` (pruned in `59bc93b`;
///    recover with `git show 59bc93b^:docs/perf-baseline-v0.1.md`)"* — the name in
///    prose, the way to get it right beside it. Requiring only the `git show` spelling
///    would make that sentence unwritable, and the reader is not stranded either way.
///    Scoped to the *same line* so the pairing is mechanical rather than a judgment
///    about how far a paragraph reaches.
/// 3. **Sibling-repo paths** (``DocCitationScanner/Citation/isSiblingRooted``): a `docs/`
///    directly after a `/` is rooted in another checkout. This is why the convention
///    for citing a sibling is `SwiftProjectLint/docs/rules/…` and not a bare `docs/…`
///    with the repo named in the surrounding English — three citations were rewritten
///    into that form when this test was written, and every one of them read as though
///    it pointed at a file in *this* repo.
///
///    **`SwiftInferProperties/docs/…` is exempt from the exemption**, and stays checked.
///    `docs/design-internal/` is copied verbatim into each sibling it describes, where
///    a bare `docs/…` resolves to nothing — so those citations name this repo on
///    purpose. Reading the repo's own name as "somewhere else" would have retired the
///    check on every path that spelling reaches.
///
/// ## What is left is a four-entry allowlist, and every entry is the same idiom
///
/// This repo documents its own broken links: *"this row said `docs/glossary.md`, which
/// does not exist."* The dead path is the **subject** of the sentence. Repointing it
/// destroys the sentence, and there is no spelling that both reads correctly and
/// resolves — so it is allowlisted with a reason, and ``allowlistEntriesAreStillThere()``
/// fails if the sentence is ever edited away, because an exemption for a citation that
/// no longer exists protects nothing while reading as though it does.
@Suite("Doc prose citations — every `docs/…` path named in a live doc resolves")
struct DocProseCitationTests {

    @Test("no live doc's prose cites a `docs/…` path that does not exist")
    func proseCitationsResolve() throws {
        let dangling = try Self.proseCitations()
            .filter { !Self.isAllowlisted($0) }
            .filter { !DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute($0.path)) }

        #expect(
            dangling.isEmpty,
            """
            These docs name a `docs/…` path in prose that does not exist. Either fix \
            the path, or — if the doc was pruned — name it with its recovery pointer \
            on the same line, e.g. `docs/foo.md` (pruned in `abc1234`; recover with \
            `git show abc1234^:docs/foo.md`). If it lives in a sibling checkout, write \
            the repo into the path: `SwiftProjectLint/docs/rules/bar.md`:
            \(DocCitationScanner.render(dangling))
            """
        )
    }

    /// The allowlist is four sentences *about* broken paths. If one is rewritten, its
    /// entry stops describing anything — and a stale exemption is worse than none,
    /// because it silently licenses whatever moves into its place.
    @Test("every allowlisted prose citation is still there")
    func allowlistEntriesAreStillThere() throws {
        let live = try Self.proseCitations()
        let unused = Self.allowlist.filter { entry in
            !live.contains { $0.file == entry.file && $0.path == entry.path }
        }

        #expect(
            unused.isEmpty,
            """
            These allowlist entries no longer match any citation — the prose was fixed \
            or removed, so the exemption is dead weight. Delete them:
            \(unused.map { "\($0.file) — \($0.path) (\($0.reason))" }.sorted().joined(separator: "\n"))
            """
        )
    }

    /// **A scan that reaches nothing passes.** Every exemption in this suite narrows
    /// the population, and one bad `hasPrefix` in ``scannedFiles()`` would empty it
    /// silently — the green run then means "found no broken citations" and "looked at
    /// no citations" indistinguishably. That is this repo's *confident zero*, and the
    /// only defence is to assert the denominator.
    ///
    /// The floor is deliberately far below the ~117 citations across 62 files measured
    /// on 2026-08-07: it is a smoke alarm for a scoping bug, not a metric to maintain.
    /// If docs are legitimately consolidated below it, lower it — after confirming the
    /// scan still reaches every directory under `docs/`.
    @Test("the prose scan reaches a plausible population")
    func scanIsNotEmpty() throws {
        let files = Self.scannedFiles()
        let citations = try Self.proseCitations()

        #expect(files.count >= 30, "only \(files.count) docs scanned — check scannedFiles()")
        #expect(citations.count >= 40, "only \(citations.count) prose citations found")

        // Every live subdirectory should be represented; an exclusion that swallowed
        // one whole would still clear the counts above.
        for directory in ["design", "measurements", "plans", "reference", "design-internal", "ideas"] {
            #expect(
                files.contains { $0.hasPrefix("docs/\(directory)/") },
                "docs/\(directory)/ is not being scanned at all"
            )
        }
    }

    /// Same argument one level up: an excluded file that no longer exists excludes
    /// nothing, while reading in the diff as a deliberate scoping decision.
    @Test("every excluded history file still exists")
    func historyExclusionsNameRealPaths() {
        let missing = Self.historyRoots.filter {
            !DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute($0))
        }

        #expect(
            missing.isEmpty,
            """
            These are excluded from the prose scan as history, but are not in the tree. \
            Drop the exclusion — it protects nothing and hides the next file that moves \
            into its path:
            \(missing.sorted().joined(separator: "\n"))
            """
        )
    }

    // MARK: - Scope

    /// Files whose citations record what *was* true, not what is reachable now.
    static let historyRoots = ["docs/archive", "CHANGELOG.md", "README.md"]

    struct Exemption {
        let file: String
        let path: String
        let reason: String
    }

    /// Every entry is a sentence whose subject is a path that deliberately does not
    /// resolve. There is no fix — only a choice between a correct sentence and a
    /// resolving path.
    static let allowlist: [Exemption] = [
        Exemption(
            file: "docs/README.md",
            path: "docs/glossary.md",
            reason: "the worked example of a citation that broke when its file moved"
        ),
        Exemption(
            file: "docs/README.md",
            path: "docs/Design/foo.md",
            reason: "a deliberately mis-cased path, illustrating the APFS blind spot"
        ),
        // Both sentences lived in CLAUDE.md until 2026-08-17, when the index's
        // long-form annotations were moved out of it wholesale. The prose is
        // unchanged; only the file it sits in moved.
        Exemption(
            file: "docs/reference/index-annotations.md",
            path: "docs/calibration-cycle-N-findings.md",
            reason: "quotes the pointer this line used to carry, to say it was wrong"
        ),
        Exemption(
            file: "docs/reference/index-annotations.md",
            path: "docs/glossary.md",
            reason: "quotes the stale path a row carried until 2026-08-06"
        )
    ]

    static func isAllowlisted(_ citation: DocCitationScanner.Citation) -> Bool {
        allowlist.contains { $0.file == citation.file && $0.path == citation.path }
    }

    // MARK: - Extracting citations

    /// Prose citations from every live doc, with the three exemptions already applied.
    ///
    /// The read **throws rather than skipping**, for the reason ``DocCitationTests``
    /// gives: a `try?` shortens the population silently, which is the same class of
    /// failure as the dangling citation itself.
    static func proseCitations() throws -> [DocCitationScanner.Citation] {
        var found: [DocCitationScanner.Citation] = []
        for relative in scannedFiles() {
            let text = try String(
                contentsOf: URL(fileURLWithPath: DocCitationScanner.absolute(relative)),
                encoding: .utf8
            )
            for (offset, line) in text.components(separatedBy: "\n").enumerated() {
                let onLine = DocCitationScanner.citations(in: line, file: relative, line: offset + 1)
                // A path named on a line that also carries its `git show` pointer is
                // recoverable; the reader has both the name and the way to read it.
                let recoverable = Set(onLine.filter(\.isHistorical).map(\.path))
                found.append(
                    contentsOf: onLine.filter {
                        !$0.isHistorical && !$0.isSiblingRooted && !recoverable.contains($0.path)
                    }
                )
            }
        }
        return found
    }

    /// Every markdown file under `docs/`, minus the history roots, plus `CLAUDE.md` —
    /// which is the index every session loads and cites docs more densely than any
    /// file in the tree, so leaving it out would exempt the highest-traffic citations
    /// in the repo.
    static func scannedFiles() -> [String] {
        // `AGENTS.md` is the Codex-facing twin of `CLAUDE.md`, produced by a mechanical
        // Claude -> Codex rename. That rename rewrote a real filename into one that does
        // not exist (`docs/archive/Codex-md-narrative-history.md`), and nothing caught it
        // because only `CLAUDE.md` was scanned. An index that loads every session is the
        // last place a dangling citation should sit unchecked, and there are two of them.
        var paths: [String] = ["CLAUDE.md", "AGENTS.md"]
        let docsRoot = DocCitationScanner.repositoryRoot.appendingPathComponent("docs")
        let enumerator = FileManager.default.enumerator(at: docsRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let relative = url.path.replacingOccurrences(
                of: DocCitationScanner.repositoryRoot.path + "/", with: ""
            )
            guard !historyRoots.contains(where: { relative.hasPrefix($0 + "/") || relative == $0 })
            else { continue }
            paths.append(relative)
        }
        return paths.sorted()
    }
}
