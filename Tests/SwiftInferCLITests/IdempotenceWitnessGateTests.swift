import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

// The pre-build gate for a payload-bearing idempotence witness whose payload
// isn't constructible — it returns architectural-coverage-pending before a
// wasted `swift build`, mirroring the cycle-139 refint Identifiable gate.
@Suite("Idempotence witness constructibility gate")
struct IdempotenceWitnessGateTests {

    private let now = Date(timeIntervalSince1970: 0)

    /// A fixture package root whose `Sources/MyApp/Feature.swift` declares an
    /// Action enum with a non-constructible (`Item`), a constructible (`Int`),
    /// and a payload-free case.
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IdempotenceWitnessGateTests-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let source = """
        struct Item {}
        struct Feature {
            enum Action {
                case reset
                case select(Item)
                case pick(Int)
            }
        }
        """
        try Data(source.utf8).write(to: dir.appendingPathComponent("Feature.swift"))
        return root
    }

    private func candidate() -> ReducerCandidate {
        ReducerCandidate(
            location: "F.swift:1",
            enclosingTypeName: "Feature",
            functionName: "body",
            signatureShape: .inoutStateActionReturnsEffect,
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            carrierKind: .tca
        )
    }

    private func invariant(
        family: InteractionInvariantFamily,
        predicate: String
    ) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: family,
            reducerQualifiedName: "Feature.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: family,
            reducerQualifiedName: "Feature.body",
            reducerLocation: "F.swift:1",
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            predicate: predicate,
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: now
        )
    }

    private func skip(
        family: InteractionInvariantFamily = .idempotence,
        predicate: String,
        root: URL
    ) -> InteractionVerifyOutcomeParser.Result? {
        VerifyInteractionPipeline.idempotenceWitnessConstructibilitySkip(
            invariant: invariant(family: family, predicate: predicate),
            candidate: candidate(),
            target: "MyApp",
            workingDirectory: root
        )
    }

    @Test("Non-constructible payload witness → pre-build coverage-pending skip")
    func nonConstructibleFires() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let result = try #require(skip(predicate: ".select", root: root))
        #expect(result.outcome == .architecturalCoveragePending)
        #expect(result.detail?.contains("non-constructible payload (Item)") == true)
        #expect(result.detail?.contains(".select") == true)
    }

    @Test("Constructible payload witness (Int) → no skip (build proceeds, it verifies)")
    func constructibleDoesNotFire() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(skip(predicate: ".pick", root: root) == nil)
    }

    @Test("Payload-free witness → no skip")
    func payloadFreeDoesNotFire() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(skip(predicate: ".reset", root: root) == nil)
    }

    @Test("Unknown case (not in alphabet) → no skip (build proceeds)")
    func unknownCaseDoesNotFire() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(skip(predicate: ".ghost", root: root) == nil)
    }

    @Test("Non-idempotence family → no skip")
    func nonIdempotenceDoesNotFire() throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(skip(family: .conservation, predicate: ".select", root: root) == nil)
    }
}
