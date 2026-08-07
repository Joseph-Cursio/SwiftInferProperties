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
/// - **This file.** The doc comment above quotes the very paths it exists to
///   describe, so scanning itself would report its own examples forever. Excluded by
///   name rather than by an "is it inside a code fence" rule, because the quoting is
///   prose here as often as it is a fence.
@Suite("Doc citations — every `docs/…` path named in code resolves")
struct DocCitationTests {

    @Test("no source or test comment cites a doc that does not exist")
    func citedDocsExist() throws {
        let dangling = try Self.citations()
            .filter { !$0.isHistorical }
            .filter { !Self.existsCaseSensitively(atPath: Self.absolute($0.path)) }

        #expect(
            dangling.isEmpty,
            """
            These comments cite a `docs/…` path that does not exist. Either fix the \
            path, or — if the doc was pruned — cite it through the SHA it was last \
            present at, e.g. `git show <sha>:docs/foo.md`:
            \(Self.render(dangling))
            """
        )
    }

    /// A `git show <sha>:docs/…` citation claims the doc is *gone from the tree*.
    /// If it is back, the reader is being sent to git history for a file sitting in
    /// front of them — and, worse, to a frozen old copy of a doc that has since
    /// moved on.
    @Test("no `git show <sha>:` citation names a doc that exists again")
    func historicalCitationsNameRemovedDocs() throws {
        let resurrected = try Self.citations()
            .filter(\.isHistorical)
            .filter { Self.existsCaseSensitively(atPath: Self.absolute($0.path)) }

        #expect(
            resurrected.isEmpty,
            """
            These are cited through `git show <sha>:` as though pruned, but the file \
            exists in the tree. Drop the `git show <sha>:` wrapper and cite the path \
            directly — the history copy is frozen and the live one is not:
            \(Self.render(resurrected))
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
        let docsRoot = Self.repositoryRoot.appendingPathComponent("docs")
        var broken: [String] = []

        let enumerator = FileManager.default.enumerator(at: docsRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let relative = url.path.replacingOccurrences(
                of: Self.repositoryRoot.path + "/", with: ""
            )
            for (offset, line) in text.components(separatedBy: "\n").enumerated() {
                for target in Self.markdownLinkTargets(in: line) {
                    let resolved = url.deletingLastPathComponent()
                        .appendingPathComponent(target).standardized
                    guard !Self.existsCaseSensitively(atPath: resolved.path) else { continue }
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
            Self.existsCaseSensitively(atPath: Self.absolute(real)),
            "\(real) exists with this exact spelling — the check must accept it"
        )

        for recased in ["Docs/README.md", "docs/readme.md", "docs/DESIGN/verify-edge-pass.md"] {
            #expect(
                !Self.existsCaseSensitively(atPath: Self.absolute(recased)),
                """
                `\(recased)` is a re-casing of a real path and must be rejected. \
                Accepting it is the SwiftProjectLint failure: a citation that \
                resolves on APFS and 404s on GitHub and Linux.
                """
            )
        }

        // Directories and escapes-above-the-repo take the other branch of the walk.
        #expect(Self.existsCaseSensitively(atPath: Self.absolute("docs/design")))
        #expect(!Self.existsCaseSensitively(atPath: Self.absolute("docs/Design")))
        #expect(!Self.existsCaseSensitively(atPath: "/no/such/path/anywhere.md"))
    }

    /// The `…` of `](…)` where the target is a local `.md`, with any `#fragment`
    /// dropped and `%20` decoded — the PRD filenames contain spaces, and a link to
    /// them is legitimately percent-encoded.
    static func markdownLinkTargets(in line: String) -> [String] {
        var targets: [String] = []
        var searchStart = line.startIndex
        while let open = line.range(of: "](", range: searchStart..<line.endIndex) {
            searchStart = open.upperBound
            guard let close = line.range(of: ")", range: open.upperBound..<line.endIndex)
            else { break }
            searchStart = close.upperBound
            var target = String(line[open.upperBound..<close.lowerBound])
            if let hash = target.firstIndex(of: "#") { target = String(target[..<hash]) }
            target = target.replacingOccurrences(of: "%20", with: " ")
            guard target.hasSuffix(".md"),
                  !target.hasPrefix("http://"),
                  !target.hasPrefix("https://")
            else { continue }
            targets.append(target)
        }
        return targets
    }

    // MARK: - Extracting citations

    struct Citation {
        let path: String
        /// Written as `git show <sha>:docs/…` — a deliberate pointer into history.
        let isHistorical: Bool
        let file: String
        let line: Int
    }

    static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }()

    static func absolute(_ path: String) -> String {
        repositoryRoot.appendingPathComponent(path).path
    }

    /// Does this path exist **with exactly this spelling**?
    ///
    /// `FileManager.fileExists` cannot answer that. APFS is case-*insensitive* by
    /// default, so it returns `true` for `docs/Foo.md` when the file is `docs/foo.md`
    /// — and that citation then 404s on GitHub and fails on a Linux runner. A guard
    /// built on `fileExists` is therefore blind to the one class of broken path that
    /// only breaks for other people.
    ///
    /// **This is not hypothetical, and it fooled this suite's own author.** On
    /// 2026-08-07 a sweep of SwiftProjectLint reported three doc paths as resolving.
    /// That repo's directory is `Docs/`, capitalised; all three said `docs/`. Every
    /// check passed locally and all three were dead links on GitHub, including the
    /// README's front-door index. The tell was `git diff` printing a path with
    /// different casing than the one that had just been edited.
    ///
    /// So: walk the path a component at a time and require each name to appear
    /// *verbatim* in its parent's directory listing, which reports true on-disk
    /// casing. Anchored at ``repositoryRoot`` when the path is inside the repo —
    /// that prefix comes from `#filePath`, so its casing is the compiler's and not
    /// a citation's — and from `/` otherwise, since a relative doc link may point at
    /// a sibling checkout.
    static func existsCaseSensitively(atPath path: String) -> Bool {
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        let anchor = repositoryRoot.path
        guard standardized != anchor else { return true }
        guard standardized.hasPrefix("/") else { return false }

        let insideRepository = standardized.hasPrefix(anchor + "/")
        var current = insideRepository ? anchor : "/"
        let remaining = (insideRepository
            ? standardized.dropFirst(anchor.count + 1)
            : standardized.dropFirst()
        ).components(separatedBy: "/")

        for component in remaining where !component.isEmpty {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: current),
                  entries.contains(component)
            else { return false }
            current = URL(fileURLWithPath: current).appendingPathComponent(component).path
        }
        return true
    }

    static func render(_ citations: [Citation]) -> String {
        citations
            .map { "\($0.file):\($0.line) — \($0.path)" }
            .sorted()
            .joined(separator: "\n")
    }

    /// Every `docs/…` citation under `Sources/` and `Tests/`.
    ///
    /// The read **throws rather than skipping**. A `try?` would drop any file it
    /// could not open and quietly shorten the population, which is precisely the
    /// under-reporting this test exists to catch.
    static func citations() throws -> [Citation] {
        var found: [Citation] = []
        for root in ["Sources", "Tests"] {
            let url = repositoryRoot.appendingPathComponent(root)
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil)
            while let fileURL = enumerator?.nextObject() as? URL {
                guard fileURL.pathExtension == "swift" else { continue }
                // This suite's own prose quotes example paths; see the type doc.
                guard fileURL.lastPathComponent != "DocCitationTests.swift" else { continue }
                let text = try String(contentsOf: fileURL, encoding: .utf8)
                let relative = fileURL.path.replacingOccurrences(
                    of: repositoryRoot.path + "/", with: ""
                )
                for (offset, line) in text.components(separatedBy: "\n").enumerated() {
                    found.append(
                        contentsOf: citations(in: line, file: relative, line: offset + 1)
                    )
                }
            }
        }
        return found
    }

    /// Doc paths in this repo contain spaces (`docs/SwiftInferProperties PRD v1.0.md`),
    /// so a character-class regex cannot bound them. Anchoring on the *extension*
    /// instead: a citation runs from `docs/` to the first following `.md` / `.json`
    /// on the same line, with the usual comment punctuation treated as a terminator
    /// so `` `docs/a.md` §6 `` and `(../../docs/a.md)` both land on the path alone.
    static func citations(in line: String, file: String, line lineNumber: Int) -> [Citation] {
        var found: [Citation] = []
        var searchStart = line.startIndex
        while let marker = line.range(of: "docs/", range: searchStart..<line.endIndex) {
            searchStart = marker.upperBound
            let remainder = line[marker.upperBound...]
            // Stop before punctuation that closes a citation rather than sitting
            // inside one; `.` and `-` and spaces are all legitimate mid-path.
            let terminator = remainder.firstIndex { "`)],;\"".contains($0) } ?? remainder.endIndex
            let candidate = remainder[remainder.startIndex..<terminator]
            guard let end = Self.extensionEnd(of: candidate) else { continue }
            let path = "docs/" + candidate[candidate.startIndex..<end]
            found.append(
                Citation(
                    path: path,
                    isHistorical: Self.isHistoricalPrefix(line[line.startIndex..<marker.lowerBound]),
                    file: file,
                    line: lineNumber
                )
            )
        }
        return found
    }

    /// The index just past the first `.md` / `.json`, or nil when the candidate
    /// carries no extension at all — prose like `docs/M6`, which is not a path.
    static func extensionEnd(of candidate: Substring) -> Substring.Index? {
        let extensions = [".md", ".json"]
        return extensions
            .compactMap { candidate.range(of: $0)?.upperBound }
            .min()
    }

    /// True for `git show <sha>:docs/…`, including the quoted form the shell needs
    /// when the path contains a space: `git show <sha>:'docs/… .md'`.
    static func isHistoricalPrefix(_ prefix: Substring) -> Bool {
        var text = prefix
        if text.hasSuffix("'") { text = text.dropLast() }
        guard text.hasSuffix(":") else { return false }
        let sha = text.dropLast().suffix(while: \.isHexDigit)
        return (7...40).contains(sha.count)
    }
}

private extension Substring {
    /// The maximal trailing run satisfying `predicate`.
    func suffix(while predicate: (Character) -> Bool) -> Substring {
        var index = endIndex
        while index > startIndex, predicate(self[self.index(before: index)]) {
            index = self.index(before: index)
        }
        return self[index...]
    }
}
