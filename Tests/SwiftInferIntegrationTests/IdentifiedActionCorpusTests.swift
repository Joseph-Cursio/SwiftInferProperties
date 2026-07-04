import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Item 2 slice 3 — fast (no-subprocess) proof that discovery → resolve → emit
/// constructs a canonical `IdentifiedAction.element(id:action:)` value against
/// the real `tca-identified-action-corpus`. `resolveAndEmit` is pure (discover
/// + emit source strings, no `swift build`), so this runs in the fast path and
/// pins the emitted expression without waiting on the ~70s measured build.
@Suite("TCA identified-action corpus — resolve + emit (slice 3)")
struct IdentifiedActionCorpusTests {

    @Test("RowList's rows(IdentifiedActionOf<Row>) resolves to a canned .element")
    func resolvesAndEmitsElement() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-identified-action-corpus-resolve")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCAIdentifiedActionCorpus",
            fromSourcesDirectory: Self.fixtureDirectory,
            into: parent
        )

        let (candidate, stub) = try VerifyInteractionPipeline.resolveAndEmit(
            target: "TCAIdentifiedActionCorpus",
            pinRaw: "RowList.body",
            workingDirectory: root
        )
        #expect(candidate.qualifiedName == "RowList.body")

        // The composition case is resolved (child Row → UUID id + payload-free
        // `increment`) and the stub constructs the canned zero-UUID element.
        #expect(stub.contains(
            ".element(id: UUID(uuidString: \"00000000-0000-0000-0000-000000000000\")!, "
            + "action: Row.Action.increment)"
        ))

        // Slice-3 payoff: `rows` is now explored (constructible), not excluded.
        let rows = candidate.actionCases.first { $0.name == "rows" }
        #expect(rows?.resolvedElement != nil)
        #expect(ActionSequenceStubEmitter.excludedCaseNames(candidate).contains("rows") == false)
    }

    static let fixtureDirectory: URL = {
        URL(fileURLWithPath: #filePath, isDirectory: false)
            .deletingLastPathComponent()  // SwiftInferIntegrationTests/
            .deletingLastPathComponent()  // Tests/
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("tca-identified-action-corpus")
    }()
}
