import Foundation
import Testing

/// The shared machinery behind ``DocCitationTests`` and ``DocProseCitationTests``:
/// pull `docs/…` paths out of a line, and answer whether one exists *with exactly
/// that spelling*.
///
/// It lives apart from either suite because both need it and neither owns it — and
/// because the two ask opposite questions of the same extraction. ``DocCitationTests``
/// scans Swift comments, where `../../docs/a.md` does mean this repo;
/// ``DocProseCitationTests`` scans markdown, where a `docs/` after a `/` means a
/// sibling checkout. The difference is recorded on ``Citation`` rather than decided
/// here, so each caller applies its own reading of the same facts.
enum DocCitationScanner {

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

    struct Citation {
        let path: String
        /// Written as `git show <sha>:docs/…` — a deliberate pointer into history.
        let isHistorical: Bool
        /// The `docs/` sat directly after a `/`, so the path is rooted somewhere else:
        /// `SwiftPropertyLaws/docs/…`, `../../SwiftIdempotency/docs/…`, `…/docs/…`.
        /// Recorded rather than filtered here, because the two populations want
        /// opposite answers — a Swift comment saying `../../docs/a.md` does mean *this*
        /// repo, while a doc naming `SwiftProjectLint/docs/…` does not.
        /// ``DocProseCitationTests`` is the consumer.
        ///
        /// One root is **not** a sibling: this repo's own name. See
        /// ``isOwnRepositoryPrefix(_:)`` — `SwiftInferProperties/docs/…` is a checkable
        /// path wearing a prefix, not an unreachable one.
        let isSiblingRooted: Bool
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

    /// A guard for citations has to quote broken citations to explain itself, so both
    /// of these files fail their own check by construction. Excluded by name rather
    /// than by an "is it inside a code fence" rule, because the quoting is prose here
    /// as often as it is a fence.
    static let selfDescribingFiles: Set<String> = [
        "DocCitationScanner.swift",
        "DocCitationTests.swift",
        "DocProseCitationTests.swift"
    ]

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
                // These suites' own prose quotes example paths; see the type doc.
                guard !Self.selfDescribingFiles.contains(fileURL.lastPathComponent)
                else { continue }
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
            // A glob names a *set*, not a file, and this repo argues about globs
            // constantly — the sweep rule is literally "sweep `docs/**/*.md`, not
            // `docs/*.md`". Checking one for existence asks the wrong question.
            guard !candidate.contains("*") else { continue }
            guard let end = Self.extensionEnd(of: candidate) else { continue }
            let path = "docs/" + candidate[candidate.startIndex..<end]
            let prefix = line[line.startIndex..<marker.lowerBound]
            found.append(
                Citation(
                    path: path,
                    isHistorical: Self.isHistoricalPrefix(prefix),
                    isSiblingRooted: prefix.hasSuffix("/") && !Self.isOwnRepositoryPrefix(prefix),
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
    /// when the path contains a space: `git show <sha>:'docs/… .md'` or `…:"docs/… .md"`.
    ///
    /// **`<sha>^:` and `<sha>~N:` count too, and missing them was a real bug.** A doc
    /// pruned *by* commit `X` is unreadable at `X` — the last commit that still has it
    /// is `X^`, so the recovery pointer a reader can actually run names the parent.
    /// That is the form three annotations in the PRDs use. The original check ran
    /// `suffix(while: isHexDigit)` straight off the `:`, so `^` terminated the run at
    /// zero digits and the citation read as ordinary prose — flagged as dangling while
    /// being the one form that is guaranteed to resolve.
    static func isHistoricalPrefix(_ prefix: Substring) -> Bool {
        var text = prefix
        if text.hasSuffix("'") || text.hasSuffix("\"") { text = text.dropLast() }
        guard text.hasSuffix(":") else { return false }
        text = text.dropLast()
        if text.hasSuffix("^") {
            text = text.dropLast()
        } else if text.last?.isNumber == true {
            let digits = text.suffix(while: \.isNumber)
            if text.dropLast(digits.count).hasSuffix("~") {
                text = text.dropLast(digits.count + 1)
            }
        }
        let sha = text.suffix(while: \.isHexDigit)
        return (7...40).contains(sha.count)
    }

    /// Is this `docs/` rooted in **this** repo, spelled with the repo's own name?
    ///
    /// `SwiftInferProperties/docs/design/foo.md` sits directly after a `/`, so the
    /// sibling test above reads it as another checkout and stops checking it. It is
    /// not another checkout — it is this one, named. That spelling exists because
    /// `docs/design-internal/` is **copied verbatim into the sibling repos it
    /// describes**, where a bare `docs/…` resolves to nothing; writing the repo in
    /// is what makes the copy readable. Excluding it would trade a live check for a
    /// spelling change, which is the expensive direction: these are exactly the
    /// paths this guard *can* verify.
    ///
    /// The prefix is stripped by the caller's `path`, so existence is checked
    /// against `docs/…` as usual.
    static func isOwnRepositoryPrefix(_ prefix: Substring) -> Bool {
        prefix.hasSuffix("SwiftInferProperties/")
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
