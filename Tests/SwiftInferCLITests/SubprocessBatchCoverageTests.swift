import Foundation
import Testing

/// The Makefile's two subprocess-routing rules, checked against the suites that
/// actually exist.
///
/// ## Why this is a test and not a comment
///
/// It was a comment — *"Keep every regex-matched suite in exactly one batch"* — and
/// CLAUDE.md restates it as a standing instruction (*"a new `*MeasuredTests` suite
/// must also be added to a Makefile BATCH by hand, or `make test` silently skips
/// it"*). **It drifted nine times.** On 2026-08-05 there were 48 suites matching
/// `SUBPROCESS_RE` and 39 in batches; the other nine had never been run by
/// `make test-fast` *or* `make test`, in either direction, ever.
///
/// It went unnoticed for the reason this repo keeps recording: **the failure is an
/// absence.** A suite that is never scheduled produces no output, and a green
/// `make test` looks identical whether it ran 48 suites or 39.
///
/// ## The two rules are different failures, so both are asserted
///
/// - **Matched but unbatched → never runs.** The fast path skips it by regex and no
///   batch names it. Silent under-testing.
/// - **`.subprocess` but unmatched → runs in the "fast" path.** A suite that spawns
///   real `swift build`s inside `make test-fast` is the ~90-minute "fast" run the
///   Makefile's own header records, from the era when the skip list enumerated suite
///   names instead of using a regex.
///
/// Both are read from the Makefile rather than restated here. A guard that hardcodes
/// the thing it guards only checks that two copies agree.
@Suite("Makefile subprocess routing — every suite is scheduled exactly once")
struct SubprocessBatchCoverageTests {

    @Test("every suite matching SUBPROCESS_RE is in exactly one batch")
    func matchedSuitesAreBatchedExactlyOnce() throws {
        let makefile = try Self.makefileText()
        let pattern = try #require(Self.assignment("SUBPROCESS_RE", in: makefile))
        let alternatives = pattern.components(separatedBy: "|")
        let batches = Self.batches(in: makefile)
        #expect(!batches.isEmpty, "no BATCHn assignments found — did the Makefile change shape?")

        var orphaned: [String] = []
        var duplicated: [String] = []
        for suite in try Self.declaredSuiteTypeNames() {
            guard alternatives.contains(where: { suite.contains($0) }) else { continue }
            // Substring containment, matching how `--filter` treats a batch value:
            // an unanchored match against the test ID.
            let covering = batches.filter { _, patterns in
                patterns.contains { suite.contains($0) }
            }
            if covering.isEmpty { orphaned.append(suite) }
            if covering.count > 1 {
                duplicated.append("\(suite) → \(covering.keys.sorted().joined(separator: ", "))")
            }
        }

        #expect(
            orphaned.isEmpty,
            """
            These suites are skipped by the fast path and named by no batch, so they \
            never run under `make test-fast` OR `make test`:
            \(orphaned.sorted().joined(separator: "\n"))
            """
        )
        #expect(
            duplicated.isEmpty,
            """
            These suites are named by more than one batch, so `make test` builds them \
            twice — the batches are sized to bound peak temp-disk:
            \(duplicated.sorted().joined(separator: "\n"))
            """
        )
    }

    /// `.tags(.subprocess)` marks *shells out to another process*; `SUBPROCESS_RE`
    /// excludes *costs minutes and a build directory*. Those are not the same set,
    /// and this is where they legitimately differ.
    ///
    /// An explicit allowlist with a reason per row, not a residual — the shape
    /// `CatalogTemplateTagDriftTests` settled on. A suite added here is a claim that
    /// it is cheap enough to belong in the fast path, and it has to be argued.
    static let deliberatelyInTheFastPath: [String: String] = [
        "PackageProductResolverTests":
            "shells out to `swift package dump-package`, which evaluates a manifest — "
            + "seconds, no `.build`. It runs inside the 28s fast suite without moving "
            + "it. Batching a cheap suite costs coverage on every `make test-fast`.",
        "PersistEvidenceOptOutTests":
            "shells out to `git ls-files` / `git rev-parse` on paths already in this "
            + "checkout — milliseconds, no network, no `.build`. The point of the suite "
            + "is that the tracked-file warning fires on a REAL tracked file, so a fake "
            + "would test the fake."
    ]

    @Test("every .subprocess suite is matched by SUBPROCESS_RE")
    func subprocessSuitesAreSkippedByTheFastPath() throws {
        let makefile = try Self.makefileText()
        let pattern = try #require(Self.assignment("SUBPROCESS_RE", in: makefile))
        let alternatives = pattern.components(separatedBy: "|")

        let unmatched = try Self.declaredSuiteTypeNames(taggedSubprocessOnly: true)
            .filter { suite in !alternatives.contains { suite.contains($0) } }
            .filter { Self.deliberatelyInTheFastPath[$0] == nil }

        #expect(
            unmatched.isEmpty,
            """
            These suites are `.tags(.subprocess)` — they spawn real `swift build`s — \
            but SUBPROCESS_RE does not match them, so `make test-fast` RUNS them. \
            Rename to the `*MeasuredTests` / `VerifyPipeline*` convention or widen \
            the regex:
            \(unmatched.sorted().joined(separator: "\n"))
            """
        )
    }

    /// An allowlist entry for a suite that no longer exists — or no longer carries
    /// the tag — protects nothing and reads as though it does. Same failure mode as
    /// the five `parallel-enum-shape` directives that suppress nothing.
    @Test("no allowlist entry is stale")
    func allowlistEntriesStillDescribeRealSuites() throws {
        let tagged = Set(try Self.declaredSuiteTypeNames(taggedSubprocessOnly: true))
        let stale = Self.deliberatelyInTheFastPath.keys.filter { !tagged.contains($0) }
        #expect(
            stale.isEmpty,
            """
            These are allowlisted as deliberately-in-the-fast-path but are no longer \
            `.tags(.subprocess)` suites — delete the entry:
            \(stale.sorted().joined(separator: "\n"))
            """
        )
    }

    // MARK: - Reading the Makefile and the suite declarations

    static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }()

    static func makefileText() throws -> String {
        try String(
            contentsOf: repositoryRoot.appendingPathComponent("Makefile"), encoding: .utf8
        )
    }

    /// The right-hand side of `NAME := …`, or nil.
    static func assignment(_ name: String, in makefile: String) -> String? {
        for line in makefile.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ":=")
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces) == name else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// `BATCH1` → its alternatives. Discovered by prefix rather than enumerated, so
    /// adding `BATCH8` does not need an edit here.
    static func batches(in makefile: String) -> [String: [String]] {
        var found: [String: [String]] = [:]
        for line in makefile.components(separatedBy: "\n") {
            let parts = line.components(separatedBy: ":=")
            guard parts.count == 2 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            guard name.hasPrefix("BATCH") else { continue }
            found[name] = parts[1].trimmingCharacters(in: .whitespaces)
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return found
    }

    /// Every test-suite type name under `Tests/`, optionally only those carrying
    /// `.tags(.subprocess)`.
    ///
    /// Read from the `@Suite` attribute's own declaration rather than from a list:
    /// the tag and the type name must travel together, and a list would be one more
    /// thing to keep in step.
    ///
    /// The read **throws rather than skipping**. A `try?` here would drop any file it
    /// could not open and quietly shorten the population — under-reporting suites is
    /// precisely the failure this test exists to catch, so it must not be able to
    /// commit it internally.
    static func declaredSuiteTypeNames(taggedSubprocessOnly: Bool = false) throws -> [String] {
        let testsRoot = repositoryRoot.appendingPathComponent("Tests")
        var names: [String] = []
        let enumerator = FileManager.default.enumerator(
            at: testsRoot, includingPropertiesForKeys: nil
        )
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            names.append(
                contentsOf: suiteTypeNames(in: text, taggedSubprocessOnly: taggedSubprocessOnly)
            )
        }
        return names
    }

    /// A `@Suite` attribute sits directly on its declaration, so the type name is the
    /// next `struct` after the attribute. Scanning forward rather than regexing the
    /// pair in one shot keeps multi-line `@Suite(…)` spellings readable.
    static func suiteTypeNames(in text: String, taggedSubprocessOnly: Bool) -> [String] {
        var names: [String] = []
        var pendingIsSubprocess: Bool?
        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("@Suite") {
                pendingIsSubprocess = line.contains(".tags(.subprocess)")
                continue
            }
            guard let isSubprocess = pendingIsSubprocess else { continue }
            // Tolerates a trailing tag line between the attribute and the struct.
            if line.contains(".tags(.subprocess)") {
                pendingIsSubprocess = true
                continue
            }
            guard let name = structName(in: line) else { continue }
            if !taggedSubprocessOnly || isSubprocess { names.append(name) }
            pendingIsSubprocess = nil
        }
        return names
    }

    static func structName(in line: String) -> String? {
        for prefix in ["struct ", "public struct ", "final class ", "public final class "]
        where line.hasPrefix(prefix) {
            let rest = line.dropFirst(prefix.count)
            let name = rest.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            return name.isEmpty ? nil : String(name)
        }
        return nil
    }
}
