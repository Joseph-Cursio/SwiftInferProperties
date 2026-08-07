import Foundation
import Testing

/// Every doc under `docs/` carries a status header, drawn from a closed vocabulary.
///
/// ## Why this is a test
///
/// `docs/README.md` splits the directory on two axes: the **directory** says what a
/// doc is, the **status header** says where it is in its life. The second only works
/// if it is actually present and actually means something — and a convention about
/// markdown is the easiest kind to let slide, because nothing compiles it.
///
/// The concrete failure it prevents is a ninth category appearing by accident.
/// `withdrawn` and `superseded` are different claims — the first says *these numbers
/// are retracted, the diagnoses may stand*, the second says *this was replaced* —
/// and a doc labelled `retracted` or `deprecated` reads as though it means one of
/// them while belonging to neither. Once two spellings exist, the header stops being
/// something a reader can scan and starts being something they have to interpret.
///
/// ## Why the vocabulary is duplicated here rather than parsed from README
///
/// It is not duplicated: ``allowedStatuses`` is read **out of** `docs/README.md`'s
/// status table. A guard that restates the thing it guards only checks that two
/// copies agree, which is the mistake `SubprocessBatchCoverageTests` calls out and
/// `CuratedEntryRole` shipped.
@Suite("Doc status headers — present, and from the closed vocabulary")
struct DocStatusHeaderTests {

    @Test("every doc under docs/ has a status header on line 3")
    func everyDocHasAStatusHeader() throws {
        let missing = try Self.docs()
            .filter { Self.statusHeader(in: $0.text) == nil }
            .map(\.path)

        #expect(
            missing.isEmpty,
            """
            These docs have no `> **Status:** …` line directly under their title. \
            Add one — see docs/README.md for the vocabulary:
            \(missing.sorted().joined(separator: "\n"))
            """
        )
    }

    @Test("every status is one of the documented values")
    func everyStatusIsInTheVocabulary() throws {
        let allowed = try Self.allowedStatuses()
        #expect(allowed.count >= 5, "parsed too few statuses from docs/README.md — did its table change shape?")

        let offenders = try Self.docs().compactMap { doc -> String? in
            guard let status = Self.statusHeader(in: doc.text)?.status else { return nil }
            return allowed.contains(status) ? nil : "\(doc.path) — `\(status)`"
        }

        #expect(
            offenders.isEmpty,
            """
            These docs carry a status outside the vocabulary in docs/README.md \
            (\(allowed.sorted().joined(separator: ", "))). Either use an existing \
            value or add the new one to README's table with what it means:
            \(offenders.sorted().joined(separator: "\n"))
            """
        )
    }

    /// A header whose date is in the future, or unparseable, is worse than none: the
    /// whole point of `As of` is that a `measured` doc reads as an expiry stamp.
    @Test("every `As of` date parses and is not in the future")
    func everyDateIsSane() throws {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let today = Date()

        let offenders = try Self.docs().compactMap { doc -> String? in
            guard let header = Self.statusHeader(in: doc.text) else { return nil }
            guard let date = formatter.date(from: header.date) else {
                return "\(doc.path) — unparseable date `\(header.date)`"
            }
            // A day of slack: the header is written by hand in local time.
            guard date.timeIntervalSince(today) > 86_400 else { return nil }
            return "\(doc.path) — future date `\(header.date)`"
        }

        #expect(offenders.isEmpty, "\(offenders.sorted().joined(separator: "\n"))")
    }

    // MARK: - Reading

    static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .deletingLastPathComponent()  // repo root
    }()

    struct Doc {
        let path: String
        let text: String
    }

    /// Throws rather than skipping — silently shortening the population is the
    /// failure this suite exists to catch, so it must not commit it internally.
    static func docs() throws -> [Doc] {
        let docsRoot = repositoryRoot.appendingPathComponent("docs")
        var found: [Doc] = []
        let enumerator = FileManager.default.enumerator(at: docsRoot, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "md" else { continue }
            let relative = url.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")
            found.append(Doc(path: relative, text: try String(contentsOf: url, encoding: .utf8)))
        }
        return found
    }

    /// `> **Status:** \`shipped\` · **As of:** 2026-08-02`, which must sit directly
    /// under the title — a status buried mid-document is one a reader scrolls past.
    static func statusHeader(in text: String) -> (status: String, date: String)? {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 2, lines[2].hasPrefix("> **Status:**") else { return nil }
        let line = lines[2]
        guard let status = line.slice(between: "`", and: "`"),
              let date = line.components(separatedBy: "**As of:**").last?
                  .trimmingCharacters(in: .whitespaces),
              !date.isEmpty
        else { return nil }
        return (status, date)
    }

    /// The status values README documents, read from the leading cell of each row in
    /// its status table: `| \`shipped\` | The work landed… |`.
    static func allowedStatuses() throws -> Set<String> {
        let readme = try String(
            contentsOf: repositoryRoot.appendingPathComponent("docs/README.md"), encoding: .utf8
        )
        var found: Set<String> = []
        for line in readme.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("| `"), let value = trimmed.slice(between: "`", and: "`")
            else { continue }
            // The kind table's first column is a directory (`reference/`); the status
            // table's is a bare word. The trailing slash is what separates them.
            guard !value.hasSuffix("/") else { continue }
            found.insert(value)
        }
        return found
    }
}

private extension String {
    /// The text between the first `open` and the next `close` after it.
    func slice(between open: String, and close: String) -> String? {
        guard let start = range(of: open),
              let end = range(of: close, range: start.upperBound..<endIndex)
        else { return nil }
        return String(self[start.upperBound..<end.lowerBound])
    }
}
