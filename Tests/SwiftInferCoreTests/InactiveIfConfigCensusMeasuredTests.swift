import Foundation
import SwiftInferTemplates
import SwiftParser
import SwiftSyntax
import Testing

@testable import SwiftInferCore

/// **How many laws does the tool propose for code that is not in the build?**
///
/// `open-threads.md` row **74**. `SwiftSyntax` parses every `#if` branch into the tree and
/// `FunctionScanner` walks it `.sourceAccurate` (`FunctionScanner.swift:136`), so a
/// declaration inside an **inactive** branch is scanned as if it were live. Nothing in
/// `Sources/` reads `IfConfigDeclSyntax`, `configuredRegions` or an active-clause rewriter.
///
/// The exhibit that surfaced it: `verify` emitted `monotonicity` rows for `RigidSet` and
/// `UniqueSet`, both under `#if UnstableHashedContainers`, and both failed with
/// `cannot find 'UniqueSet' in scope` — `Package.swift` has that trait commented out of
/// `.default(enabledTraits:)`.
///
/// ## Scope: WHOLE-FILE guards only, and that is a deliberate under-count
///
/// The measured shape in `swift-collections` is a file whose entire content sits inside one
/// `#if` — all 54 `UnstableSortedCollections` files are of that form. **This reading counts
/// only that shape**, because it is decidable from the file's own top level and needs no
/// judgement about where a declaration sits within nested clauses.
///
/// **So every figure here is a FLOOR.** A declaration inside an inner `#if` block is
/// invisible to it, and `swift-collections` alone holds 16 `COLLECTIONS_INTERNAL_CHECKS`
/// and 23 `#if false` blocks that are not whole-file. Naming the under-count is the point:
/// row 74 says a grep is the wrong instrument, and an over-claiming parser would be worse.
///
/// ## What counts as inactive, and what deliberately does not
///
/// - `#if false` — inactive, definitionally.
/// - `#if SomeBareIdentifier` — **presumed** inactive: a custom flag or a package trait,
///   off unless someone passes it. This is the target.
/// - `#if compiler(…)`, `#if swift(…)`, `#if os(…)`, `#if canImport(…)`, `#if arch(…)`,
///   `#if targetEnvironment(…)` — **not counted**. These are usually active, and sweeping
///   them would be this row's version of *gating on `@available` would sweep 1,163
///   `deprecated`*. `swift-collections` alone has 303 `#if compiler` blocks.
/// - `#if DEBUG` — **not counted.** It is a bare identifier and it is ON in a debug build,
///   which is what the generated suites are built as.
///
/// ⚠ **"Presumed inactive" CAN be wrong, and MEASURABLY IS — 2 of the 11 conditions this
/// found are defined by their own package.** That is why the reading prints files *and
/// rows* per condition: only the row column can be subtracted.
///
/// | condition | rows | status, hand-checked against the manifest |
/// |---|---:|---|
/// | `UnstableSortedCollections` | 50 | **inactive** — commented out of `.default(enabledTraits:)` |
/// | `FOUNDATION_FRAMEWORK` | 58 | **inactive** — never `.define`d in the package build |
/// | `UnstableHashedContainers` | 1 | **inactive** — commented out, the original exhibit |
/// | `SQLITE_ENABLE_FTS5` | 6 | ⚠ **ACTIVE** — GRDB `.define`s it unconditionally |
/// | `DATA_LEGACY_ABI` | 6 | ⚠ **ACTIVE** — `.define(…, .when(platforms: [.macOS, …]))` |
/// | the four `SWIFT_*` stdlib flags | 17 | **unresolved** — CMake flags, no manifest to read |
///
/// **So of 138 presumed: 109 confirmed inactive, 12 measured FALSE, 17 unresolved.** The
/// suite asserts the total it measures, not the corrected figure, because the correction
/// comes from reading manifests by hand and belongs in the doc where it can be dated.
///
/// **The flags are NOT added to `notCounted`.** Two corpora's build settings are not a
/// property of the rule, and hard-coding them would make the heuristic look more accurate
/// than it is — the reader needs to see the false-positive rate to judge the rest.
@Suite("Census — laws proposed for code behind an inactive #if", .serialized)
struct InactiveIfConfigCensusMeasuredTests {

    /// Directive-style conditions that are usually ACTIVE, plus `DEBUG`.
    static let notCounted: Set<String> = [
        "compiler", "swift", "os", "canImport", "arch", "targetEnvironment", "hasFeature",
        "hasAttribute", "_runtime", "_endian", "_pointerBitWidth", "DEBUG"
    ]

    /// `true` when the condition is one this reading presumes OFF in a default build.
    static func isPresumedInactive(_ condition: ExprSyntax) -> Bool {
        let text = condition.trimmedDescription
        if text == "false" { return true }
        // A bare identifier and nothing else. `FOO && BAR`, `!FOO`, `os(macOS)` all fall out
        // here — a compound condition is not decidable this cheaply and is left uncounted.
        guard let reference = condition.as(DeclReferenceExprSyntax.self) else { return false }
        return !notCounted.contains(reference.baseName.text)
    }

    /// The condition of the single `#if` wrapping a file's entire top level, or `nil`.
    ///
    /// "Entire top level" tolerates leading `import` declarations, which sit outside the
    /// guard in several of the measured files, and nothing else.
    static func wholeFileGuard(of source: String) -> String? {
        let tree = Parser.parse(source: source)
        var found: IfConfigDeclSyntax?
        for statement in tree.statements {
            if let declaration = statement.item.as(DeclSyntax.self),
               declaration.is(ImportDeclSyntax.self) { continue }
            guard let ifConfig = statement.item.as(IfConfigDeclSyntax.self) else { return nil }
            guard found == nil else { return nil }
            found = ifConfig
        }
        guard let ifConfig = found else { return nil }
        // Only a bare `#if X … #endif` counts. An `#else` means the file contributes
        // declarations either way, so it is never wholly absent from the build.
        guard ifConfig.clauses.count == 1,
              let clause = ifConfig.clauses.first,
              let condition = clause.condition,
              isPresumedInactive(condition)
        else { return nil }
        return condition.trimmedDescription
    }

    /// **The exclusions `scripts/measurement.py` owns, applied by construction.**
    ///
    /// That module exists because six instrument errors in one cycle came from a corpus
    /// walk that counted the wrong files, and it is the canonical list:
    /// `(".build", ".git", "checkouts", "Tests", ".swiftinfer")`.
    ///
    /// ⚠ **The first run of this census applied NONE of them**, and reported `#if
    /// UnstableSortedCollections` in **188** files where the package holds **54** — the
    /// surplus was `swift-collections` vendored inside other corpora's `.build/checkouts`.
    /// It was caught only because a direct `grep` of that package had been run minutes
    /// earlier and disagreed. **A count with no independent reading beside it would have
    /// shipped.**
    static let excludedDirectories = [".build", ".git", "checkouts", "Tests", ".swiftinfer"]

    static func isExcluded(_ url: URL) -> Bool {
        let components = url.pathComponents
        return excludedDirectories.contains { components.contains($0) }
    }

    /// Every `.swift` file under the manifest's corpora, with `excludedDirectories`
    /// applied, keyed to the whole-file guard condition where there is one.
    ///
    /// **Text prefilter before parsing**: most files hold no `#if` at all, and parsing every
    /// file in twenty corpora a second time is the cost this reading lives inside an
    /// existing census to avoid.
    struct Walk {
        /// File path → the whole-file guard condition, for files that have one.
        let guarded: [String: String]
        /// Every `.swift` file the walk considered — the denominator, which
        /// `scripts/measurement.py` requires be returned alongside any population.
        let scanned: Int
        /// Those containing `#if` at all, so the prefilter's reach is visible.
        let withIfConfig: Int
    }

    static func walkCorpora() -> Walk {
        var guarded: [String: String] = [:]
        var scanned = 0
        var withIfConfig = 0
        for corpus in CorpusManifest.available {
            let enumerator = FileManager.default.enumerator(
                at: corpus.primaryRoot, includingPropertiesForKeys: nil
            )
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension == "swift", !isExcluded(url) else { continue }
                guard let source = try? String(contentsOf: url, encoding: .utf8) else { continue }
                scanned += 1
                guard source.contains("#if") else { continue }
                withIfConfig += 1
                if let condition = wholeFileGuard(of: source) { guarded[url.path] = condition }
            }
        }
        return Walk(guarded: guarded, scanned: scanned, withIfConfig: withIfConfig)
    }

    /// The per-corpus, per-template and carrier breakdowns of the affected rows.
    static func breakdowns(of affected: [CatalogHealthCensusMeasuredTests.Row]) -> [String] {
        var lines: [String] = []
        for (title, grouped) in [
            ("affected rows by corpus:", Dictionary(grouping: affected) { $0.corpus }.mapValues(\.count)),
            ("affected rows by template:", Dictionary(grouping: affected) { $0.template }.mapValues(\.count))
        ] {
            lines.append("")
            lines.append(title)
            for (key, count) in grouped.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
                lines.append("  \(count)  \(key)")
            }
        }
        lines.append("")
        lines.append("carriers, which is row 74's sharpest unchecked question:")
        let carriers = Dictionary(grouping: affected.compactMap(\.carrier)) { $0 }.mapValues(\.count)
        for (carrier, count) in carriers.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }).prefix(15) {
            lines.append("  \(count)  \(carrier)")
        }
        return lines
    }

    @Test("census — discovery rows whose file is entirely behind an inactive #if")
    func inactiveConditionCensus() {
        let walk = Self.walkCorpora()
        let guardedFiles = walk.guarded
        let filesScanned = walk.scanned
        let filesWithAnyIfConfig = walk.withIfConfig

        let rows = CatalogHealthCensusMeasuredTests.rows
        let affected = rows.filter { guardedFiles[$0.file] != nil }

        var lines: [String] = ["", "INACTIVE #if — ALL MANIFEST CORPORA", ""]
        lines.append("swift files scanned \(filesScanned) · containing any #if \(filesWithAnyIfConfig)"
            + " · WHOLE-FILE guarded by a presumed-inactive condition \(guardedFiles.count)")
        lines.append("discovery rows \(rows.count) · rows in such a file **\(affected.count)**")

        lines.append("")
        lines.append("conditions matched — files AND ROWS, because only the row column can be")
        lines.append("subtracted when a manifest turns out to define the flag after all:")
        let byCondition = Dictionary(grouping: guardedFiles.values) { $0 }.mapValues(\.count)
        var rowsByCondition: [String: Int] = [:]
        for row in affected {
            guard let condition = guardedFiles[row.file] else { continue }
            rowsByCondition[condition, default: 0] += 1
        }
        for (condition, count) in byCondition.sorted(by: { ($0.value, $1.key) > ($1.value, $0.key) }) {
            let rows = rowsByCondition[condition] ?? 0
            let label = "#if \(condition)".padding(toLength: 44, withPad: " ", startingAt: 0)
            lines.append("  \(label)\(count) file(s)  \(rows) row(s)")
        }

        if !affected.isEmpty { lines += Self.breakdowns(of: affected) }
        print(lines.joined(separator: "\n"))

        // **The control.** This reading's whole value is a count that could be zero, and a
        // zero from a broken file walk is indistinguishable from a zero from a clean
        // corpus. Assert the denominator, not the finding.
        #expect(filesScanned > 1_000, "the file walk found only \(filesScanned) Swift files")
        #expect(filesWithAnyIfConfig > 0, "no file contains `#if` — the prefilter is broken")
        #expect(!rows.isEmpty, "the census produced no discovery rows")
    }
}
