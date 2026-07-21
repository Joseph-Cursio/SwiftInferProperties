import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// The gap that hid the wasted build: the gate function was tested in
/// isolation, but nothing proved the *pipeline* reaches it and short-circuits
/// the build for a non-constructible-payload witness. This drives the real
/// `runWithInvariant` entry and asserts it returns the gate's DISCLOSED skip
/// (`non-constructible payload`) rather than a post-build `swift build failed`
/// — which is only possible if the gate fired *before* `executeAndParse`.
///
/// It is a **fast** test on purpose: because the gate short-circuits, no
/// `swift build` runs (the fixture is discovery-valid but never compiled). If
/// the gate were unwired, `runWithInvariant` would fall through to a real
/// build — the test would then hang / fail on the build, exactly the signal
/// that was missing.
@Suite("Idempotence witness gate — pipeline wiring")
struct IdempotenceWitnessGateWiringTests {

    @Test("runWithInvariant short-circuits a non-constructible witness before building")
    func gateShortCircuitsBeforeBuild() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IdempotenceWitnessGateWiring-\(UUID().uuidString)")
        let dir = root.appendingPathComponent("Sources").appendingPathComponent("MyApp")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A discovery-valid @Reducer whose Action has a payload-free
        // constructible case (so the `.tca` generator gate passes) plus a
        // payload-BEARING witness with a non-constructible payload (`Item`).
        let source = """
        import ComposableArchitecture
        struct Item: Equatable {}
        @Reducer
        struct Feature {
            @ObservableState struct State: Equatable { var value = 0 }
            enum Action { case reset, select(Item) }
            var body: some ReducerOf<Self> {
                Reduce { state, action in .none }
            }
        }
        """
        try Data(source.utf8).write(to: dir.appendingPathComponent("Feature.swift"))

        let invariant = idempotenceInvariant(predicate: ".select")
        let result = try VerifyInteractionPipeline.runWithInvariant(
            target: "MyApp",
            invariant: invariant,
            persistEvidence: false,
            workingDirectory: root
        )

        // The gate's disclosed skip — proof it fired pre-build. A build-fail
        // path would instead carry "swift build failed".
        #expect(result.outcome == .architecturalCoveragePending)
        #expect(result.detail?.contains("non-constructible payload (Item)") == true)
        #expect(result.detail?.contains("swift build failed") != true)
    }

    private func idempotenceInvariant(predicate: String) -> InteractionInvariantSuggestion {
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: "Feature.body",
            predicate: predicate
        )
        return InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: "Feature.body",
            reducerLocation: "Feature.swift:1",
            stateTypeName: "Feature.State",
            actionTypeName: "Feature.Action",
            predicate: predicate,
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 0)
        )
    }
}
