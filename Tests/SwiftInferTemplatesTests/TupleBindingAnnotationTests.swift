import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// **A multi-argument stub's property closure must name its tuple's type** (#498).
///
/// `property: { args in … }` gives the type-checker nothing to anchor `args` on: its type comes
/// from the `sample` closure's return, a tuple of large generic expressions. Swift answers
/// *cannot infer type of closure parameter 'args' without a type annotation* — the
/// second-largest cause of a stub failing to compile on the 16 September corpus funnel re-run,
/// at 288 stubs.
@Suite("Multi-argument stubs — the tuple is annotated")
struct TupleBindingAnnotationTests {

    private func callee(_ name: String, labels: [String?]) -> CalleeReference {
        CalleeReference(
            bareName: name,
            qualifier: "Subject",
            argumentLabels: labels,
            isInstanceMethod: true
        )
    }

    @Test("a tuple binding names each drawn value's type, in argument order")
    func tupleIsAnnotated() {
        let stub = LiftedTestEmitter.total(
            callee: callee("annotate", labels: [nil, "metadata"]),
            seed: SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generators: ["Subject.gen()", "Gen<String>.string()", "Meta.gen()"],
            isThrowing: false,
            isAsync: false,
            argumentTypes: ["Subject", "String", "Meta"]
        )
        #expect(stub.contains("{ (args: (Subject, String, Meta)) in"))
        #expect(!stub.contains("{ args in"), "the bare binding is what does not compile")
    }

    /// **The fallback is load-bearing.** A caller that cannot supply types must emit exactly what
    /// it emitted before, so this change cannot alter a stub it has nothing to say about.
    @Test("no types means the binding is unchanged")
    func missingTypesFallBack() {
        #expect(LiftedTestEmitter.tupleBinding(argumentTypes: [], count: 3) == "args")
    }

    /// A count that disagrees is a bug upstream, not a licence to emit a wrong annotation:
    /// annotating a 3-tuple with 2 types produces code that cannot compile for a new reason.
    @Test("a disagreeing count falls back rather than emitting a wrong annotation")
    func mismatchedCountFallsBack() {
        #expect(LiftedTestEmitter.tupleBinding(argumentTypes: ["A", "B"], count: 3) == "args")
    }

    /// The single-value form is deliberately untouched — it already has its own annotation path
    /// through `makeTestStub(carrierType:)`, and changing it here would move existing stubs.
    @Test("a one-generator stub still binds `value`")
    func singleValueIsUnchanged() {
        let stub = LiftedTestEmitter.total(
            callee: callee("isValid", labels: [nil]),
            seed: SamplingSeed.Value(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            generators: ["Gen<String>.string()"],
            isThrowing: false,
            isAsync: false,
            argumentTypes: ["String"]
        )
        #expect(stub.contains("{ value in"))
    }
}
