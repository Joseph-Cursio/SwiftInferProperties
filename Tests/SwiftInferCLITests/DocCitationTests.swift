import Foundation
import Testing

/// Every `docs/…` path cited from a source or test comment, checked against the
/// files that actually exist.
///
/// ## Why this is a test and not a convention
///
/// This repo cites docs from code constantly — 117 Swift files carry a `docs/`
/// path, and for several decisions the cited doc is the *only* recorded rationale
/// (CLAUDE.md says so outright of `roadtest-self-dogfood.md`: 19 live sites cite
/// its diagnoses). A citation is load-bearing here in a way a stray link is not.
///
/// **It had already broken, silently, in two directions.** On 2026-08-07 there
/// were 16 distinct dangling `docs/…` paths across ~30 sites:
///
/// - `docs/glossary.md` moved to `docs/design-internal/glossary.md`. CLAUDE.md's own
///   row was corrected on 2026-08-06 — *"path corrected; this row said
///   `docs/glossary.md`, which does not exist"* — and the two Swift files saying the
///   same thing were not. (Quoted as history, and this file is excluded from the
///   scan, so neither path here is a live citation.)
/// - The per-cycle findings docs and the perf baselines were pruned from the tree
///   across five commits (539 files). Twenty-odd comments still named them.
///
/// Both are the failure this repo keeps re-recording: **the failure is an
/// absence.** A comment pointing at nothing compiles, lints, and reads exactly
/// like a comment pointing at something. Nothing reports it, so a doc move looks
/// free at the moment you make it and costs a reader their only rationale later.
///
/// ## Removed docs are cited through git, not deleted from the comment
///
/// A pruned doc is still *recoverable*, and the diagnosis in it did not stop being
/// true — so the convention is to cite the SHA it was last present at rather than
/// drop the reference:
///
/// ```swift
/// /// See `git show 31a347a:docs/calibration-cycle-63-findings.md`.
/// ```
///
/// That form is exempt from the existence check and asserted in the *opposite*
/// direction by ``historicalCitationsNameRemovedDocs()``: if the path comes back,
/// the `git show` wrapper is now the wrong citation and the test says so. The two
/// directions fail differently, which is why both are asserted — same reasoning as
/// `SubprocessBatchCoverageTests`.
///
/// ## What this deliberately does not catch
///
/// - **A path split across two comment lines.** Extraction is line-scoped, so
///   ``docs/calibration-cycle-50-\n// findings.md`` reads as prose and is skipped.
///   One such site existed and was joined rather than accommodated — a rule that
///   bends around its exceptions stops being checkable.
/// - **A reference with no file extension.** Prose in practice, and treating those
///   as paths would make the test argue with English.
/// - **This file, and ``DocProseCitationTests``.** A guard for citations has to quote
///   broken citations to explain itself, so both would report their own examples
///   forever. Excluded by name (``selfDescribingFiles``) rather than by an "is it
///   inside a code fence" rule, because the quoting is prose here as often as it is
///   a fence.
/// - **A glob.** `docs/**/*.md` names a set, not a file — and this repo argues about
///   globs often enough that treating one as a path produced ten false positives the
///   first time the prose scan ran.
@Suite("Doc citations — every `docs/…` path named in code resolves")
struct DocCitationTests {

    @Test("no source or test comment cites a doc that does not exist")
    func citedDocsExist() throws {
        let dangling = try DocCitationScanner.citations()
            .filter { !$0.isHistorical }
            .filter { !DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute($0.path)) }

        #expect(
            dangling.isEmpty,
            """
            These comments cite a `docs/…` path that does not exist. Either fix the \
            path, or — if the doc was pruned — cite it through the SHA it was last \
            present at, e.g. `git show <sha>:docs/foo.md`:
            \(DocCitationScanner.render(dangling))
            """
        )
    }

    /// A `git show <sha>:docs/…` citation claims the doc is *gone from the tree*.
    /// If it is back, the reader is being sent to git history for a file sitting in
    /// front of them — and, worse, to a frozen old copy of a doc that has since
    /// moved on.
    @Test("no `git show <sha>:` citation names a doc that exists again")
    func historicalCitationsNameRemovedDocs() throws {
        let resurrected = try DocCitationScanner.citations()
            .filter(\.isHistorical)
            .filter { DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute($0.path)) }

        #expect(
            resurrected.isEmpty,
            """
            These are cited through `git show <sha>:` as though pruned, but the file \
            exists in the tree. Drop the `git show <sha>:` wrapper and cite the path \
            directly — the history copy is frozen and the live one is not:
            \(DocCitationScanner.render(resurrected))
            """
        )
    }

    /// Cross-doc links are *relative*, so every one of them breaks when a doc changes
    /// directory — and unlike the prose citations above, they break in a way a reader
    /// only discovers by clicking. The 2026-08-07 reorganisation moved 64 docs at
    /// once, which is exactly the operation that needs this.
    ///
    /// Scoped to markdown link syntax (`](…)`) rather than prose mentions of a path.
    /// A link is unambiguously a claim that the target is reachable; a path named in
    /// a sentence may be history (`docs/archive/claude-md-narrative-history.md` is a
    /// copy of an old CLAUDE.md — verbatim in prose — and cites docs that were pruned
    /// years of commits ago, correctly, since it is a record of what was once written.
    /// Its paths to docs that merely *moved* were repointed on 2026-08-07; the ones to
    /// pruned docs were deliberately left dangling, so this file stays a permanent
    /// source of unresolvable prose citations and must not be swept into the check).
    @Test("every relative markdown link between docs resolves")
    func relativeDocLinksResolve() throws {
        let docsRoot = DocCitationScanner.repositoryRoot.appendingPathComponent("docs")
        var broken: [String] = []

        let enumerator = FileManager.default.enumerator(at: docsRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(
                of: DocCitationScanner.repositoryRoot.path + "/", with: ""
            )
            for (offset, line) in text.components(separatedBy: "\n").enumerated() {
                for target in DocCitationScanner.markdownLinkTargets(in: line) {
                    let resolved = url.deletingLastPathComponent()
                        .appendingPathComponent(target).standardized
                    guard !DocCitationScanner.existsCaseSensitively(atPath: resolved.path) else { continue }
                    broken.append("\(relative):\(offset + 1) — \(target)")
                }
            }
        }

        #expect(
            broken.isEmpty,
            """
            These markdown links point at a doc that is not there. Relative links move \
            with the file, so a doc that changed directory needs its links recomputed \
            against the new depth — not just its own path updated:
            \(broken.sorted().joined(separator: "\n"))
            """
        )
    }

    /// The three assertions above are only as good as ``existsCaseSensitively(atPath:)``,
    /// and the thing it replaces looked correct for months. So it is checked directly
    /// rather than trusted: an exact spelling resolves, a re-cased one does not.
    ///
    /// Deliberately **not** asserted here: that `FileManager.fileExists` disagrees.
    /// It does today, on a default APFS volume, and that disagreement is the whole
    /// reason this helper exists — but pinning it would make the suite fail on a
    /// case-sensitive volume, where the two agreeing is the *correct* outcome.
    @Test("the case-sensitive existence check distinguishes spellings")
    func caseSensitiveCheckRejectsRecasedPaths() {
        let real = "docs/README.md"
        #expect(
            DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute(real)),
            "\(real) exists with this exact spelling — the check must accept it"
        )

        for recased in ["Docs/README.md", "docs/readme.md", "docs/DESIGN/verify-edge-pass.md"] {
            #expect(
                !DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute(recased)),
                """
                `\(recased)` is a re-casing of a real path and must be rejected. \
                Accepting it is the SwiftProjectLint failure: a citation that \
                resolves on APFS and 404s on GitHub and Linux.
                """
            )
        }

        // Directories and escapes-above-the-repo take the other branch of the walk.
        #expect(DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute("docs/design")))
        #expect(!DocCitationScanner.existsCaseSensitively(atPath: DocCitationScanner.absolute("docs/Design")))
        #expect(!DocCitationScanner.existsCaseSensitively(atPath: "/no/such/path/anywhere.md"))
    }
}
