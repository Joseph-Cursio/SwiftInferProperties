@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// V1.31.C — dispatch-table wiring from suggestion carrier type to
/// `LiftedTestEmitter.EqualityKind`. The `liftedTestStub(for:)` accept
/// path consults `FloatingPointEquatableTypes` and selects
/// `.approximate` for FP-equatable carriers, `.strict` otherwise.
@Suite("InteractiveTriage — V1.31.C equalityKind dispatch")
struct InteractiveTriageEqualityKindTests {

    @Test("V1.31.C — Double → .approximate")
    func doubleMapsToApproximate() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "Double") == .approximate)
    }

    @Test("V1.31.C — Float → .approximate")
    func floatMapsToApproximate() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "Float") == .approximate)
    }

    @Test("V1.31.C — Complex → .approximate")
    func complexMapsToApproximate() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "Complex") == .approximate)
    }

    @Test("V1.31.C — Complex<Double> → .approximate (generic-stripped)")
    func complexDoubleMapsToApproximate() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "Complex<Double>") == .approximate)
    }

    @Test("V1.31.C — Complex<RealType> → .approximate")
    func complexRealTypeMapsToApproximate() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "Complex<RealType>") == .approximate)
    }

    @Test("V1.31.C — Int → .strict")
    func intMapsToStrict() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "Int") == .strict)
    }

    @Test("V1.31.C — String → .strict")
    func stringMapsToStrict() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "String") == .strict)
    }

    @Test("V1.31.C — custom user type → .strict")
    func customTypeMapsToStrict() {
        #expect(InteractiveTriage.equalityKind(forTypeText: "MyToken") == .strict)
        #expect(InteractiveTriage.equalityKind(forTypeText: "Array<Int>") == .strict)
    }

    @Test("V1.31.C — OrderedSet → .strict")
    func orderedSetMapsToStrict() {
        // The cycle-25 OC idempotence-lifted picks (sort, _regenerate*,
        // _isUnique) all use OrderedSet as carrier — must continue to
        // emit strict == for the test to compile against Equatable.
        #expect(InteractiveTriage.equalityKind(forTypeText: "OrderedSet") == .strict)
        #expect(InteractiveTriage.equalityKind(forTypeText: "OrderedDictionary") == .strict)
    }
}
