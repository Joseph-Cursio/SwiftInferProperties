import Foundation
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// Cycle 122 (Phase A) — the capstone: a *real* TCA `@Reducer` verified
/// end-to-end through the production pipeline to `measured-bothPass`. The
/// fixture is deliberately real-shaped — `internal` (not public), `@Reducer`
/// + `@ObservableState`, a payload-free `enum Action` that does **not**
/// declare `CaseIterable` — i.e. the exact `tca-25-discovery` shape that
/// was unverifiable before this cycle. Exercises every Phase-A piece:
/// discovery's `actionCaseNames` capture, the emitter's instance-relative
/// `.tca` apply + explicit-case generator, and VerifierWorkdir's
/// `.interactionTCA` direct-source-inclusion build.
///
/// Spawns a real `swift build` that resolves swift-composable-architecture
/// (pulls swift-syntax for the macros) — minutes on a cold cache. Tagged
/// `.subprocess`; skipped in the fast path.
@Suite("TCA carrier — Phase A measured verify", .tags(.subprocess))
struct TCACarrierMeasuredTests {

    /// Real TCA reducer with an idempotent witness `.closeMenu`
    /// (`menuOpen = false`, twice == once). `internal`, macro-based,
    /// non-`CaseIterable` Action — nothing here is sanitized for the
    /// verifier.
    private static let counterSource = """
    import ComposableArchitecture

    @Reducer
    struct Counter {
        @ObservableState
        struct State: Equatable {
            var count = 0
            var menuOpen = false
        }
        enum Action {
            case increment
            case decrement
            case closeMenu
        }
        var body: some Reducer<State, Action> {
            Reduce { state, action in
                switch action {
                case .increment:
                    state.count += 1
                    return .none
                case .decrement:
                    state.count -= 1
                    return .none
                case .closeMenu:
                    state.menuOpen = false
                    return .none
                }
            }
        }
    }
    """

    @Test("a real @Reducer with a payload-free Action verifies bothPass")
    func realTCAReducerMeasuresBothPass() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-carrier-measured")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        // Stage the corpus. The dependency-free manifest CorpusPackager
        // writes is never built — the `.tca` path inlines these sources into
        // the verifier target instead — it only anchors the package root +
        // the discovery `Sources/<module>/` layout.
        let root = try CorpusPackager.package(
            moduleName: "TCACounterCorpus",
            sourceFiles: [.init(name: "Counter.swift", contents: Self.counterSource)],
            into: parent
        )

        // The idempotence witness on the real reducer (qualifiedName
        // `Counter.body`; the bare-pin path resolves it). Construct the
        // invariant directly — this test proves the verify mechanics, not
        // the witness detector.
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: "Counter.body",
            predicate: ".closeMenu"
        )
        let invariant = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: "Counter.body",
            reducerLocation: "Sources/TCACounterCorpus/Counter.swift:3",
            stateTypeName: "Counter.State",
            actionTypeName: "Counter.Action",
            predicate: ".closeMenu",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let result = try VerifyInteractionPipeline.runWithInvariant(
            target: "TCACounterCorpus",
            invariant: invariant,
            workingDirectory: root
        )

        // The whole point: a real TCA reducer now executes and the
        // idempotent witness holds across 1024 sequences.
        #expect(result.outcome == .measuredBothPass)

        // Evidence persisted under the witness identity (the producer half
        // of the M9 join), so discover-interaction would promote it.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.record(for: invariant.identity.normalized)?.outcome == .measuredBothPass)
    }

    /// Cycle 125 (Phase B) — a MIXED Action: free witness + a raw-payload
    /// case (generated) + a non-derivable case (skipped). Proves relaxed
    /// partial exploration verifies the witness and discloses the excluded
    /// case in the evidence detail (guardrail #1).
    private static let mixedSource = """
    import ComposableArchitecture
    import Foundation

    @Reducer
    struct Mixed {
        @ObservableState
        struct State: Equatable {
            var count = 0
            var menuOpen = false
            var data: Data?
        }
        enum Action {
            case closeMenu          // free — idempotent witness
            case setCount(Int)      // raw payload — generated
            case received(Data)     // non-derivable — skipped
        }
        var body: some Reducer<State, Action> {
            Reduce { state, action in
                switch action {
                case .closeMenu: state.menuOpen = false; return .none
                case let .setCount(n): state.count = n; return .none
                case let .received(d): state.data = d; return .none
                }
            }
        }
    }
    """

    @Test("Phase B — mixed Action verifies the witness + discloses the excluded case")
    func mixedActionPartialExploration() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("tca-carrier-mixed")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let root = try CorpusPackager.package(
            moduleName: "TCAMixedCorpus",
            sourceFiles: [.init(name: "Mixed.swift", contents: Self.mixedSource)],
            into: parent
        )
        let canonical = InteractionInvariantSuggestion.identityCanonicalInput(
            family: .idempotence,
            reducerQualifiedName: "Mixed.body",
            predicate: ".closeMenu"
        )
        let invariant = InteractionInvariantSuggestion(
            identity: SuggestionIdentity(canonicalInput: canonical),
            family: .idempotence,
            reducerQualifiedName: "Mixed.body",
            reducerLocation: "Sources/TCAMixedCorpus/Mixed.swift:4",
            stateTypeName: "Mixed.State",
            actionTypeName: "Mixed.Action",
            predicate: ".closeMenu",
            score: 40,
            tier: .likely,
            whySuggested: [],
            whyMightBeWrong: [],
            firstSeenAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let result = try VerifyInteractionPipeline.runWithInvariant(
            target: "TCAMixedCorpus",
            invariant: invariant,
            workingDirectory: root
        )

        #expect(result.outcome == .measuredBothPass)
        // Guardrail #1: the partial-exploration basis is disclosed.
        #expect(result.detail?.contains("excluded: received") == true)
        #expect(result.detail?.contains("explored 2 of 3 action types") == true)
        // …and the disclosure rides into the persisted evidence.
        let stored = VerifyEvidenceStore.load(startingFrom: root)
        #expect(stored.log.record(for: invariant.identity.normalized)?
            .detail?.contains("excluded: received") == true)
    }
}
