import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// Value monotonicity (`a ≤ b ⟹ f(a) ≤ f(b)`) orders the input domain with
// `min`/`max`, so a non-Comparable domain can't be verified. The emitter
// pre-flights the domain's Comparable-ness and throws
// `VerifyError.monotonicityDomainNotComparable` — mapping to a clean
// architectural-coverage-pending outcome that SKIPS the doomed build —
// rather than emitting a `min`/`max` stub that build-fails.
@Suite("StrategistDispatchEmitter — monotonicity domain Comparable pre-flight")
struct MonotonicityDomainGateTests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    /// A memberwise-generatable struct shape with the given conformances — so
    /// `resolveRecipe` derives a `Gen<name>` and the emit reaches the
    /// monotonicity pre-flight (the domain must be generatable to get there).
    private static func memberwiseShape(name: String, inheritedTypes: [String]) -> IndexedTypeShape {
        IndexedTypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: inheritedTypes,
            hasUserGen: false,
            storedMembers: [IndexedTypeShape.StoredMember(name: "size", typeName: "Int")],
            hasUserInit: true,
            initializers: [
                IndexedTypeShape.InitializerSignature(
                    parameters: [IndexedTypeShape.InitializerParameter(label: "size", typeName: "Int")]
                )
            ]
        )
    }

    private static func monotonicityInputs(
        carrier: String,
        shape: IndexedTypeShape?
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: shape,
            template: "monotonicity",
            functionCalls: ["\(carrier).score", "score(_:)"],
            extraImports: [],
            seedHex: canonicalSeed,
            trialBudget: .small,
            allShapes: shape.map { [carrier: $0] } ?? [:]
        )
    }

    @Test("a generatable non-Comparable domain throws the pre-flight error (no min/max stub)")
    func nonComparableDomainThrows() {
        let shape = Self.memberwiseShape(name: "Widget", inheritedTypes: ["Equatable"])
        do {
            _ = try StrategistDispatchEmitter.emit(Self.monotonicityInputs(carrier: "Widget", shape: shape))
            Issue.record("expected emit to throw for a non-Comparable monotonicity domain")
        } catch let error as VerifyError {
            guard case let .monotonicityDomainNotComparable(domain) = error else {
                Issue.record("wrong VerifyError: \(error)")
                return
            }
            #expect(domain == "Widget")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
    }

    @Test("a custom domain declaring Comparable passes the pre-flight and emits the min/max shape")
    func comparableCustomDomainEmits() throws {
        let shape = Self.memberwiseShape(name: "Score", inheritedTypes: ["Equatable", "Comparable"])
        let source = try StrategistDispatchEmitter.emit(Self.monotonicityInputs(carrier: "Score", shape: shape))
        // Recognized as Comparable via inheritedTypes → the value-monotonicity
        // shape emits (mirrors the Confidence corpus, which verifies).
        #expect(source.contains("let valueA = min(firstDraw, secondDraw)"))
        #expect(source.contains("let valueB = max(firstDraw, secondDraw)"))
    }

    @Test("a Comparable scalar domain passes without a shape (known-scalar fast path)")
    func comparableScalarDomainEmits() throws {
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "monotonicity",
                functionCalls: ["{ (x: Int) in x }", "score(_:)"],
                extraImports: [],
                seedHex: Self.canonicalSeed,
                trialBudget: .small
            )
        )
        #expect(source.contains("let valueA = min(firstDraw, secondDraw)"))
    }

    @Test("isComparableMonotonicityDomain: scalars true, custom keyed on inheritedTypes")
    func domainPredicate() {
        let comparableShape = Self.memberwiseShape(name: "Score", inheritedTypes: ["Comparable"])
        let plainShape = Self.memberwiseShape(name: "Widget", inheritedTypes: ["Equatable"])
        let inputs = Self.monotonicityInputs(carrier: "Score", shape: comparableShape)
        let plainInputs = StrategistDispatchEmitter.Inputs(
            carrier: "Widget", typeShape: plainShape, template: "monotonicity",
            functionCalls: [], seedHex: Self.canonicalSeed, trialBudget: .small,
            allShapes: ["Widget": plainShape]
        )
        #expect(StrategistDispatchEmitter.isComparableMonotonicityDomain("Int", inputs: inputs))
        #expect(StrategistDispatchEmitter.isComparableMonotonicityDomain("String", inputs: inputs))
        #expect(StrategistDispatchEmitter.isComparableMonotonicityDomain("Score", inputs: inputs))
        #expect(StrategistDispatchEmitter.isComparableMonotonicityDomain("Widget", inputs: plainInputs) == false)
        #expect(StrategistDispatchEmitter.isComparableMonotonicityDomain("Mystery", inputs: plainInputs) == false)
    }

    @Test("an OC instance-method monotonicity carrier is exempt (orders indices, not the carrier)")
    func instanceCarrierExempt() throws {
        // OrderedSet<Int> isn't Comparable, but its monotonicity orders Int
        // indices — the pre-flight must not throw for it.
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "OrderedSet<Int>",
                typeShape: nil,
                template: "monotonicity",
                functionCalls: ["OrderedSet.index", "index(after:)"],
                extraImports: [],
                seedHex: Self.canonicalSeed,
                trialBudget: .small
            )
        )
        #expect(source.contains("receiver.index(after: lowerIndex)"))
    }
}
