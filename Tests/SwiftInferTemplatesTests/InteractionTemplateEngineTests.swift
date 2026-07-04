import Foundation
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

// V2.0 M4.A — InteractionTemplateEngine namespace smoke tests.
// The dispatch surface fans out to every shipped per-family analyzer.
// Five families are witness-based (need sourcesDirectory); Determinism
// (Phase 2 Redux) is witness-free and surfaces one suggestion per
// redux-family candidate without source access.

@Suite("InteractionTemplateEngine — V2.0 M4.A namespace + dispatch")
struct InteractionTemplateEngineTests {

    private func candidate(
        functionName: String = "reduce",
        signatureShape: ReducerSignatureShape = .stateActionReturnsState
    ) -> ReducerCandidate {
        ReducerCandidate(
            location: "Sources/T.swift:1",
            enclosingTypeName: nil,
            functionName: functionName,
            signatureShape: signatureShape,
            stateTypeName: "S",
            actionTypeName: "A",
            carrierKind: .elmStyle
        )
    }

    @Test("empty candidate list yields empty suggestions")
    func emptyCandidates() throws {
        let result = try InteractionTemplateEngine.analyze(candidates: [])
        #expect(result.isEmpty)
    }

    @Test("without sourcesDirectory only the witness-free families surface")
    func analyzeWithoutSourcesDirectory() throws {
        // The five witness-based families (Conservation / Idempotence / …) need
        // sourcesDirectory to walk the State / Action source. Two families are
        // witness-free and surface without source access: Determinism (every
        // redux candidate) and UnknownActionIsNoOp (open-alphabet candidates —
        // these test candidates carry an empty `actionCases` set). So each
        // candidate yields two suggestions.
        let result = try InteractionTemplateEngine.analyze(candidates: [
            candidate(functionName: "reduceA"),
            candidate(functionName: "reduceB", signatureShape: .inoutStateActionReturnsVoid)
        ])
        #expect(result.count == 4)
        #expect(result.allSatisfy {
            $0.family == .determinism || $0.family == .unknownActionIsNoOp
        })
        #expect(result.filter { $0.family == .determinism }.count == 2)
        #expect(result.filter { $0.family == .unknownActionIsNoOp }.count == 2)
    }

    @Test("analyzeOne without sourcesDirectory surfaces the two witness-free families")
    func analyzeOneReturnsDeterminismWithoutDirectory() throws {
        let result = try InteractionTemplateEngine.analyzeOne(
            candidate(),
            sourcesDirectory: nil,
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
        #expect(result.count == 2)
        #expect(Set(result.map(\.family)) == [.determinism, .unknownActionIsNoOp])
    }

    @Test("Determinism now surfaces for a TCA carrier (dependency-pinned)")
    func determinismIncludesTCA() throws {
        let tcaCandidate = ReducerCandidate(
            location: "Sources/T.swift:1",
            enclosingTypeName: "Feature",
            functionName: "reduce",
            signatureShape: .inoutStateActionReturnsVoid,
            stateTypeName: "S",
            actionTypeName: "A",
            carrierKind: .tca
        )
        let result = try InteractionTemplateEngine.analyzeOne(
            tcaCandidate,
            sourcesDirectory: nil,
            firstSeenAt: ISO8601DateFormatter().date(from: "2026-05-15T10:00:00Z")!
        )
        #expect(result.contains { $0.family == .determinism })
    }

    // MARK: - V1.91 cycle-88 — bare-State / bare-Action cross-contamination fix

    @Test("bare-State witnesses scope to the candidate's own enclosing type (V1.91 fix)")
    func bareStateNoCrossContamination() throws {
        // Two reducers each declare a nested `State` struct following
        // the TCA `Reducer.State` convention. Each State has its OWN
        // distinct (count-shaped aggregate + array) pair. Pre-v1.91,
        // the bare-`State` typestack-suffix match fired witnesses from
        // every State against every reducer (8.2× inflation measured
        // on the cycle-87 hand-rolled corpus). With the v1.91 fix,
        // each reducer sees only its own witnesses.
        let directory = try makeFixtureDirectory(name: "BareStateCrossContam")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(in: directory, name: "TwoReducers.swift", contents: twoReducersFixture)
        let candidates = [
            sharedNameCandidate(enclosingTypeName: "AReducer", location: "TwoReducers.swift:10"),
            sharedNameCandidate(enclosingTypeName: "BReducer", location: "TwoReducers.swift:20")
        ]
        let suggestions = try InteractionTemplateEngine.analyze(
            candidates: candidates,
            sourcesDirectory: directory
        )
        // Only conservation should fire (AReducer.itemCount × items,
        // BReducer.entryCount × entries). Each reducer matched only
        // against its own State — total 2 suggestions, not 4 (pre-fix
        // would Cartesian-multiply: A's predicate against B's State
        // and vice versa).
        let conservation = suggestions.filter { $0.family == .conservation }
        #expect(conservation.count == 2)
        let predicates = Set(conservation.map(\.predicate))
        #expect(predicates == [
            "state.itemCount == state.items.count",
            "state.entryCount == state.entries.count"
        ])
        let perReducer = Dictionary(grouping: conservation, by: \.reducerQualifiedName)
        #expect(perReducer["AReducer.reduce"]?.count == 1)
        #expect(perReducer["BReducer.reduce"]?.count == 1)
    }

    @Test("bare-Action idempotence witnesses scope to candidate's own enclosing type")
    func bareActionNoCrossContamination() throws {
        // Same shape as the State test but exercising
        // IdempotenceWitnessDetector's actionTypeName path. Two
        // reducers with different idempotent actions; pre-v1.91 each
        // would have fired against the other's Action cases (so 2 × 2
        // = 4 suggestions instead of 1 + 1 = 2).
        let directory = try makeFixtureDirectory(name: "BareActionCrossContam")
        defer { try? FileManager.default.removeItem(at: directory) }
        try writeFile(in: directory, name: "TwoActions.swift", contents: twoActionsFixture)
        let candidates = [
            sharedNameCandidate(enclosingTypeName: "AReducer", location: "TwoActions.swift:10"),
            sharedNameCandidate(enclosingTypeName: "BReducer", location: "TwoActions.swift:20")
        ]
        let suggestions = try InteractionTemplateEngine.analyze(
            candidates: candidates,
            sourcesDirectory: directory
        )
        let idempotence = suggestions.filter { $0.family == .idempotence }
        #expect(idempotence.count == 2)
        let perReducer = Dictionary(grouping: idempotence, by: \.reducerQualifiedName)
        #expect(perReducer["AReducer.reduce"]?.first?.predicate == ".refresh")
        #expect(perReducer["BReducer.reduce"]?.first?.predicate == ".clear")
    }

    private func sharedNameCandidate(enclosingTypeName: String, location: String) -> ReducerCandidate {
        ReducerCandidate(
            location: location,
            enclosingTypeName: enclosingTypeName,
            functionName: "reduce",
            signatureShape: .stateActionReturnsState,
            stateTypeName: "State",
            actionTypeName: "Action",
            carrierKind: .generic
        )
    }

    private let twoReducersFixture = """
        struct AReducer {
            struct State {
                var itemCount: Int
                var items: [String]
            }
            enum Action { case noop }
            static func reduce(_ s: State, _ a: Action) -> State { return s }
        }
        struct BReducer {
            struct State {
                var entryCount: Int
                var entries: [Int]
            }
            enum Action { case noop }
            static func reduce(_ s: State, _ a: Action) -> State { return s }
        }
        """

    private let twoActionsFixture = """
        struct AReducer {
            struct State {}
            enum Action {
                case refresh
                case other
            }
            static func reduce(_ s: State, _ a: Action) -> State { return s }
        }
        struct BReducer {
            struct State {}
            enum Action {
                case clear
                case other
            }
            static func reduce(_ s: State, _ a: Action) -> State { return s }
        }
        """

    // MARK: - Fixture helpers

    private func makeFixtureDirectory(name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("InteractionTemplateEngineTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func writeFile(in directory: URL, name: String, contents: String) throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }
}
