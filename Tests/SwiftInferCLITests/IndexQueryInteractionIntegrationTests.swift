import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// V1.141 — end-to-end guard for the interaction-surface SemanticIndex
/// loop: `index --target` discovers reducer invariants, projects them onto
/// `InteractionIndexEntry` rows, writes them to `.swiftinfer/index.json`,
/// and `query` reads + filters + renders them. Exercises phases 1–4
/// together (Core entry + store + IndexCommand wiring + QueryCommand) on a
/// real (in-process, no build) reducer fixture.
@Suite("Index ↔ Query — V1.141 interaction surface end-to-end")
struct IndexQueryInteractionIntegrationTests {

    private final class RecordingDiag: DiagnosticOutput, @unchecked Sendable {
        private(set) var lines: [String] = []

        func writeDiagnostic(_ text: String) { lines.append(text) }
    }

    /// A minimal SwiftPM package with one free-function reducer under
    /// `Sources/AppFeature/`. `dismiss` is an idempotence witness
    /// (resets to a fixed state), so discovery surfaces an idempotence
    /// interaction invariant on `reduce`.
    private func makeReducerPackage() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IndexQueryE2E-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources").appendingPathComponent("AppFeature")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try Data("// swift-tools-version: 6.1\n".utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        try """
        public struct GateState: Equatable, Sendable {
            public var isOpen: Bool
            public init(isOpen: Bool = false) { self.isOpen = isOpen }
        }

        public enum GateAction: CaseIterable, Sendable {
            case dismiss
            case open
        }

        public func reduce(_ state: GateState, _ action: GateAction) -> GateState {
            switch action {
            case .dismiss: return GateState(isOpen: false)
            case .open: return GateState(isOpen: true)
            }
        }
        """.write(
            to: sources.appendingPathComponent("Feature.swift"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    private func runIndex(root: URL) throws -> IndexStore.Index {
        _ = try SwiftInferCommand.Index.performIndex(
            IndexInputs(
                scanDirectory: root.appendingPathComponent("Sources").appendingPathComponent("AppFeature"),
                includePossible: true,
                explicitVocabularyPath: nil,
                explicitConfigPath: nil,
                explicitTestDirPath: nil,
                packsOverride: nil,
                dryRun: false,
                targetName: "AppFeature",
                workingDirectory: root
            ),
            diagnostics: RecordingDiag()
        )
        let loaded = IndexStore.load(
            from: IndexStore.defaultPath(for: root),
            nowTimestamp: SwiftInferCommand.Index.isoTimestamp(from: Date())
        )
        return loaded.index
    }

    @Test("V1.141 — index writes interaction rows incl. an idempotence invariant")
    func indexWritesInteractionRows() throws {
        let root = try makeReducerPackage()
        defer { try? FileManager.default.removeItem(at: root) }

        let index = try runIndex(root: root)
        #expect(index.schemaVersion == IndexStore.currentSchemaVersion)
        #expect(!index.interactionEntries.isEmpty)
        #expect(index.interactionEntries.contains { $0.family == "idempotence" })
        // Every interaction row carries the display-hash + reducer identity.
        for entry in index.interactionEntries {
            #expect(entry.identityHash.hasPrefix("0x"))
            #expect(entry.reducerQualifiedName.contains("reduce"))
            #expect(entry.decision == nil)   // untriaged on a fresh index
        }
    }

    @Test("V1.141 — query --surface interaction --family idempotence renders the invariant")
    func queryFiltersInteractionSurface() throws {
        let root = try makeReducerPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try runIndex(root: root)

        let outcome = SwiftInferCommand.Query.runQuery(
            directoryOverride: nil,
            explicitIndexPath: IndexStore.defaultPath(for: root).path,
            filters: QueryFilters(family: "idempotence", surface: .interaction),
            limit: nil
        )
        #expect(outcome.matchedCount >= 1)
        #expect(outcome.rendered.contains("Interaction invariants:"))
        #expect(outcome.rendered.contains("idempotence |"))
    }

    @Test("V1.141 — query --surface algebraic is empty for a pure-reducer package")
    func queryAlgebraicSurfaceEmpty() throws {
        let root = try makeReducerPackage()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try runIndex(root: root)

        let outcome = SwiftInferCommand.Query.runQuery(
            directoryOverride: nil,
            explicitIndexPath: IndexStore.defaultPath(for: root).path,
            filters: QueryFilters(surface: .algebraic),
            limit: nil
        )
        // A reducer exposes no algebraic (pure-function) laws.
        #expect(outcome.matchedCount == 0)
        #expect(outcome.rendered == "No entries match.\n")
    }

    @Test("V1.141 — re-index preserves firstSeenAt on interaction rows")
    func reindexPreservesFirstSeenAt() throws {
        let root = try makeReducerPackage()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try runIndex(root: root)
        let firstSeen = Dictionary(
            uniqueKeysWithValues: first.interactionEntries.map { ($0.identityHash, $0.firstSeenAt) }
        )
        #expect(!firstSeen.isEmpty)

        let second = try runIndex(root: root)
        for entry in second.interactionEntries {
            #expect(entry.firstSeenAt == firstSeen[entry.identityHash], "firstSeenAt must survive re-index")
        }
    }
}
