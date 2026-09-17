import Foundation
@testable import SwiftInferCore
import Testing

/// **Which templates can `discover --interactive` propose, and write nothing for?** (#479)
///
/// Accepting a suggestion whose template has no arm in the accept path records the decision and
/// writes no file, under *"no stub writeout available for template 'X' in v1"*. That gap used to
/// be a doc comment saying there was none and a test counting *"the 8 that still take the generic
/// sentence"* without naming them — a count with no list cannot go stale visibly, and both had.
///
/// So the gap is a **list**, and this suite keeps it true in both directions:
///
/// - a template something emits and nothing writes must be on `noWriterYet`, so a new template
///   cannot join the gap silently;
/// - a template with an arm must NOT be on it, so writing an arm forces the entry's removal.
///
/// ## Both sides are read from source, deliberately
///
/// There is no runtime registry of template names — each template spells its own, as a literal or
/// as `TemplateName.x.rawValue` — and `TemplateName` is NOT the universe: it has 21 cases while 46
/// names are emitted, missing `guard-domain`, `input-totality` and `value-round-trip` among them.
/// `TemplatePack.allTemplateNames` is wrong the same way (CLAUDE.md, the catalog-health row). A
/// list restated here would be the second copy that drifts, so the universe is scanned, the way
/// `SubprocessBatchCoverageTests` reads the Makefile rather than restating it.
///
/// ⚠ **An arm is a DISPATCH, not a guarantee of a file.** An arm can still return `nil` for a
/// particular suggestion; the corpus funnel measured `round-trip` doing so once and reaching the
/// generic sentence anyway (#456's shape). This suite tracks which templates have no writer at
/// all, which is the gap #468 and #479 are about.
@Suite("Stub writers — every emitted template is written, or listed as not yet")
struct StubWriterCoverageTests {

    /// Templates something emits and the accept path has no arm for.
    ///
    /// Figures are the 20-corpus catalog-health census (6,215 rows) and the 19-repository corpus
    /// funnel's generic declines, both 2026-09-16. They size the gap; this suite asserts only
    /// membership, so they go stale without failing anything. Re-take them rather than trust them.
    /// `ENTAILED` marks `Refutability.roleEntailedTemplates` — a law a correct implementation
    /// cannot fail, which is why #468 put those first. `VERIFY` marks a template `verify` already
    /// renders through `StrategistDispatchEmitter`, so its law has an emitter to reuse — the two
    /// largest gaps are both `VERIFY`.
    static let noWriterYet: [String: String] = [
        "measure-non-negativity": "VERIFY · 442 rows · 23 funnel declines, 9 repos — the largest gap",
        "codable-round-trip": "VERIFY · 154 rows · 0 funnel declines",
        "dual-style-consistency": "VERIFY · 59 rows",
        "value-round-trip": "53 rows · 43 funnel declines, 7 repos",
        "model-law": "39 rows",
        "role-postcondition": "VERIFY · 39 rows",
        "equivalence-relation": "29 rows · 15 funnel declines, 1 repo",
        "state-machine": "ENTAILED · 28 rows · 8 funnel declines — pairing fixed in #489, writer unbuilt",
        "set-relation-model-law": "25 rows",
        "binary-idempotence": "VERIFY · 22 rows",
        "differential-equivalence": "VERIFY · 19 rows",
        "bulk-incremental-agreement": "18 rows",
        "normal-form": "ENTAILED · 17 rows · 39 funnel declines — writer DECLINED on measurement (#478)",
        "ended-access-round-trip": "16 rows",
        "functor-identity": "15 rows",
        "role-closure": "13 rows",
        "reorder-partition": "11 rows",
        "composition": "10 rows",
        "involution": "VERIFY · 10 rows · 5 funnel declines",
        "sequence-view-model-law": "9 rows",
        "homomorphism": "VERIFY · 8 rows · 3 funnel declines",
        "scaled-unit-consistency": "8 rows",
        "partition": "ENTAILED · 2 rows · 1 funnel decline",
        "caseiterable-case-coverage": "1 row · 1 funnel decline",
        "override-precedence": "1 row · 1 funnel decline",
        "multiplicative-homomorphism": "VERIFY · 0 rows at 20 corpora · 2 funnel declines",
        "selection-subset": "ENTAILED · 0 rows at 20 corpora · 1 funnel decline",
        "diff-disjointness": "ENTAILED · 0 rows at 20 corpora or in the funnel — unwitnessed"
    ]

    @Test("every emitted template has a stub arm or is listed as having none")
    func everyEmittedTemplateIsAccountedFor() throws {
        let unaccounted = try Self.emittedTemplates()
            .subtracting(Self.templatesWithArms())
            .subtracting(Self.noWriterYet.keys)
        #expect(unaccounted.isEmpty, """
        \(unaccounted.sorted()) can be proposed and nothing writes a stub for them. Add an arm in \
        `InteractiveTriage+Accept*.swift`, or add each to `noWriterYet` with its measured size — \
        silently joining the gap is what this suite exists to stop.
        """)
    }

    @Test("a template with an arm is not still listed as having none")
    func writingAnArmRemovesTheEntry() throws {
        let written = try Self.templatesWithArms().intersection(Self.noWriterYet.keys)
        #expect(written.isEmpty, """
        \(written.sorted()) now have an arm in the accept path. Remove them from `noWriterYet` — \
        a list that keeps a closed gap open reports work that is already done.
        """)
    }

    @Test("every listed template is one something still emits")
    func everyListedTemplateStillExists() throws {
        let stale = Set(Self.noWriterYet.keys).subtracting(try Self.emittedTemplates())
        #expect(stale.isEmpty, """
        \(stale.sorted()) are listed as having no writer, but nothing emits them any more. \
        Renamed or deleted — remove or rename the entry.
        """)
    }

    @Test("every arm dispatches a template something emits")
    func noArmIsDead() throws {
        let dead = try Self.templatesWithArms().subtracting(Self.emittedTemplates())
        #expect(dead.isEmpty, """
        The accept path dispatches \(dead.sorted()), which no template emits — a renamed template \
        whose arm can no longer be reached.
        """)
    }

    /// **The control.** Both scans are regular expressions over source, and a blind scan passes
    /// every assertion above vacuously: an empty universe has nothing unaccounted. So each must
    /// find names known to be there, in both spellings.
    @Test("control — neither scan is blind")
    func theScansFindKnownNames() throws {
        let emitted = try Self.emittedTemplates()
        let arms = try Self.templatesWithArms()
        #expect(emitted.count >= 40, "the source scan found \(emitted.count) template names; expected ~46")
        #expect(emitted.contains("value-round-trip"), "a literal `templateName:` was not found")
        #expect(emitted.contains("replay-idempotence"), "a `TemplateName.x.rawValue` spelling was not found")
        #expect(arms.contains("predicate"), "a `case \"…\":` arm was not found")
        #expect(arms.contains("determinism"), "a `templateName == \"…\"` arm was not found")
    }

    // MARK: - Reading the source

    static let repositoryRoot = URL(fileURLWithPath: #filePath, isDirectory: false)
        .deletingLastPathComponent()  // SwiftInferCLITests/
        .deletingLastPathComponent()  // Tests/
        .deletingLastPathComponent()  // repo root

    /// Every template name passed to a `templateName:` argument anywhere in `Sources/`.
    ///
    /// A non-literal argument (`templateName: String`, `templateName: entry.templateName`) is a
    /// declaration or a pass-through of a name already emitted elsewhere, so skipping it loses no
    /// name — checked when this was written, across every such site.
    static func emittedTemplates() throws -> Set<String> {
        let caseToRawValue = Dictionary(
            uniqueKeysWithValues: TemplateName.allCases.map { (String(describing: $0), $0.rawValue) }
        )
        var names: Set<String> = []
        for text in try sourceTexts(under: "Sources") {
            names.formUnion(matches(of: #"templateName:\s*"([a-z]+(?:-[a-z]+)*)""#, in: text))
            for caseName in matches(of: #"templateName:\s*TemplateName\.(\w+)\.rawValue"#, in: text) {
                if let rawValue = caseToRawValue[caseName] { names.insert(rawValue) }
            }
        }
        return names
    }

    /// Every template name the accept path dispatches on: `case "a", "b":` and
    /// `templateName == "a"` in `InteractiveTriage+Accept*.swift`.
    static func templatesWithArms() throws -> Set<String> {
        let directory = repositoryRoot.appendingPathComponent("Sources/SwiftInferCLI")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix("InteractiveTriage+Accept") && $0.hasSuffix(".swift") }
        var names: Set<String> = []
        for file in files {
            let text = try String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
            for caseList in matches(of: #"case ((?:"[a-z]+(?:-[a-z]+)*"(?:,\s*)?)+):"#, in: text) {
                names.formUnion(matches(of: #""([a-z]+(?:-[a-z]+)*)""#, in: caseList))
            }
            names.formUnion(matches(of: #"templateName == "([a-z]+(?:-[a-z]+)*)""#, in: text))
        }
        return names
    }

    private static func sourceTexts(under relativePath: String) throws -> [String] {
        let root = repositoryRoot.appendingPathComponent(relativePath)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return try enumerator.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
            .map { try String(contentsOf: $0, encoding: .utf8) }
    }

    /// The first capture group of every match.
    private static func matches(of pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        }
    }
}
