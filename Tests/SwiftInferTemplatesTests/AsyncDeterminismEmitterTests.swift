import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The async determinism stub (collections/async workplan Phase 4): two
/// sequentially awaited calls compared for equality, inside the backend's
/// already-async property closure — no scaffold change.
@Suite
struct AsyncDeterminismEmitterTests {

    private static let seed = SamplingSeed.Value(
        stateA: 0x1, stateB: 0x2, stateC: 0x3, stateD: 0x4
    )

    @Test
    func asyncFormAwaitsBothSidesOfTheEquality() {
        let source = LiftedTestEmitter.deterministic(
            funcName: "fetchLabel",
            parameters: [.init(label: nil, generator: "Gen<Int>.int(in: -10_000 ... 10_000)")],
            seed: Self.seed,
            isAsync: true
        )
        #expect(source.contains("@Test func fetchLabel_isDeterministic() async {"))
        #expect(source.contains(
            "property: { value in (await fetchLabel(value)) == (await fetchLabel(value)) }"
        ))
    }

    @Test
    func syncFormIsUnchangedByTheNewParameter() {
        let source = LiftedTestEmitter.deterministic(
            funcName: "describe",
            parameters: [.init(label: nil, generator: "Gen<Int>.int()")],
            seed: Self.seed
        )
        // The scaffold's own `await backend.check(` is expected; the property
        // closure itself must stay await-free in the sync form.
        #expect(source.contains("property: { value in describe(value) == describe(value) }"))
    }
}
