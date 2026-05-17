import Foundation
import Testing
@testable import SwiftInferTemplates

// V1.103 (cycle-100 Finding A fix) — regression tests for the
// distinct-field dedupe in CardinalityWitnessDetector's
// directory-walk entry. Real TCA 1.25.5 hits this through the
// SharedState examples (02-SharedState-{FileStorage,InMemory,
// UserDefaults}.swift each define their own CounterTab.State with
// a single Optional alert field), so the regression is grounded in
// observed corpus data rather than a synthetic edge case.

@Suite("CardinalityWitnessDetector — V1.103 cross-file distinct-field dedupe")
struct CardinalityDistinctFieldDedupeTests {

    /// Helper — write `files` to a fresh temp directory, run the
    /// directory-walk entry, return the witnesses.
    private func detectAcrossFiles(
        targetName: String,
        files: [String: String]
    ) throws -> [CardinalityWitness] {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("cardinality-dedupe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        for (name, source) in files {
            try source.write(
                to: tempDirectory.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        return try CardinalityWitnessDetector.detect(
            stateTypeName: targetName,
            in: tempDirectory
        )
    }

    @Test("three files each defining CounterTab.State with the same `alert` field → no witness")
    func multiFileSameNameSingleField() throws {
        // Mirrors the TCA 1.25.5 SharedState examples — 3 distinct
        // `CounterTab.State` types in 3 files, each with one
        // `alert: ...?` field. Pre-v1.103, the directory walk
        // concatenated to 3 fields and emitted a malformed
        // predicate `(alert != nil) + (alert != nil) + (alert != nil)
        // <= 1`. Post-fix, the dedupe collapses to 1 field, which
        // fails the `≥ 2 distinct fields` guard.
        let template = """
        struct CounterTab {
            struct State {
                var alert: AlertState<Action>?
            }
        }
        """
        let witnesses = try detectAcrossFiles(
            targetName: "CounterTab.State",
            files: [
                "FileStorage.swift": template,
                "InMemory.swift": template,
                "UserDefaults.swift": template
            ]
        )
        #expect(witnesses.isEmpty)
    }

    @Test("two files with same-named structs holding different fields → 2 distinct, witness fires")
    func multiFileDifferentFieldsAggregates() throws {
        // Two files each declare AppState (independent definitions
        // would be a compile error in a real Swift module, but the
        // detector's syntactic walk is module-agnostic). Each
        // contributes a distinct field — the dedupe is a no-op
        // because property names don't collide. Mirrors the
        // CounterTab.body multi-file case but with non-overlapping
        // fields so the cardinality predicate is well-formed.
        //
        // **Why not test `extension AppState { ... }`?** The visitor
        // currently only handles StructDecl / ClassDecl / EnumDecl,
        // not ExtensionDecl, so the doc comment's "extension split"
        // case is aspirational. Testing the actually-walked shape
        // documents the dedupe's real semantics: it gates against
        // duplicated fields from multiple typewise-distinct matches,
        // not against extension splits.
        let fileOne = """
        struct AppState {
            var activeSheet: SheetKind?
        }
        """
        let fileTwo = """
        struct AppState {
            var activeAlert: AlertKind?
        }
        """
        let witnesses = try detectAcrossFiles(
            targetName: "AppState",
            files: ["sheet.swift": fileOne, "alert.swift": fileTwo]
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].fields.count == 2)
        let names = Set(witnesses[0].fields.map(\.propertyName))
        #expect(names == ["activeSheet", "activeAlert"])
    }

    @Test("three files with overlapping fields: 2 distinct after dedupe → witness fires")
    func multiFileOverlapStillProducesValidPredicate() throws {
        // Mixed case: 3 files, two of them define `activeSheet`,
        // the third defines `activeAlert`. Post-dedupe: 2 distinct
        // fields (`activeSheet` + `activeAlert`). Witness fires
        // with a well-formed 2-slot predicate, not a 3-slot one
        // with `activeSheet` repeated.
        let sheetFile = """
        struct AppState {
            var activeSheet: SheetKind?
        }
        """
        let alertFile = """
        struct AppState {
            var activeAlert: AlertKind?
        }
        """
        let witnesses = try detectAcrossFiles(
            targetName: "AppState",
            files: [
                "a-sheet.swift": sheetFile,
                "b-sheet.swift": sheetFile,
                "c-alert.swift": alertFile
            ]
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].fields.count == 2)
        let names = Set(witnesses[0].fields.map(\.propertyName))
        #expect(names == ["activeSheet", "activeAlert"])
    }

    @Test("single-file detection unchanged by the dedupe path")
    func singleFileDetectionPathUnchanged() {
        // The single-source entry doesn't go through the dedupe —
        // it returns whatever the single visitor walk produced. A
        // file declaring two distinct Optional presentation fields
        // still fires.
        let source = """
        struct AppState {
            var activeSheet: SheetKind?
            var activeAlert: AlertKind?
        }
        """
        let witnesses = CardinalityWitnessDetector.detect(
            stateTypeName: "AppState",
            in: source
        )
        #expect(witnesses.count == 1)
        #expect(witnesses[0].fields.count == 2)
    }
}
