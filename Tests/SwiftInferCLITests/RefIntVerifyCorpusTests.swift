import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 138 — fast guard on the checked-in referential-integrity verify
/// corpus (`Tests/Fixtures/refint-verify-corpus/`): packaging + discovery
/// surfaces exactly the two intended refint identities at the `.possible`
/// baseline (no evidence yet). Discovery is AST-only, so this is fast; the
/// measured baseline (refint is the fifth and final family to get a
/// measured-verify path) is `RefIntVerifyCorpusMeasuredTests`.
@Suite("Referential-integrity verify corpus — discovery coverage (cycle 138)")
struct RefIntVerifyCorpusTests {

    @Test("packaging + discovery surfaces exactly the two refint identities at .possible")
    func discoversTheCuratedIdentities() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("refint-verify-corpus-discovery")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "RefIntVerifyCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let suggestions = try SwiftInferCommand.DiscoverInteraction.collectSuggestions(
            target: "RefIntVerifyCorpus",
            workingDirectory: root
        )
        let refint = suggestions.filter { $0.family == .referentialIntegrity }
        let found = Set(refint.map { "\($0.reducerQualifiedName) \($0.predicate)" })

        let expected: Set<String> = [
            "LibraryFeature.body state.selectedBookID == nil"
                + " || state.books.contains { $0.id == state.selectedBookID }",
            "CatalogFeature.body state.selectedItemID == nil"
                + " || state.items.contains { $0.id == state.selectedItemID }"
        ]
        #expect(found == expected)

        // Un-gated baseline: refint sits at .possible before any measured run.
        #expect(refint.allSatisfy { $0.tier == .possible })

        // The corpus surfaces no other family (one selected* Optional × one
        // matching collection per reducer; no count/array, no presentation
        // slots, no Bool/Optional pair, no witness-vocab action names).
        #expect(suggestions.allSatisfy { $0.family == .referentialIntegrity })
    }

    /// `Tests/Fixtures/refint-verify-corpus/`, resolved against `#filePath`
    /// so it holds regardless of `swift test`'s cwd.
    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferCLITests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("refint-verify-corpus")
    }()
}
