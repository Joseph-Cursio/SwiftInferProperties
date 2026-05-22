@testable import SwiftInferCore
import Testing

/// V1.31.A — curated set + detector for FP-equatable types. Drives the
/// `LiftedTestEmitter` `EqualityKind` dispatch (V1.31.B).
@Suite("FloatingPointEquatableTypes — V1.31.A curated set + detector")
struct FloatingPointEquatableTypesTests {

    // MARK: - Set membership

    @Test("Curated set contains stdlib Real types")
    func curatedSetContainsRealTypes() {
        #expect(FloatingPointEquatableTypes.curated.contains("Double"))
        #expect(FloatingPointEquatableTypes.curated.contains("Float"))
        #expect(FloatingPointEquatableTypes.curated.contains("Float16"))
        #expect(FloatingPointEquatableTypes.curated.contains("Float80"))
        #expect(FloatingPointEquatableTypes.curated.contains("CGFloat"))
    }

    @Test("Curated set contains Complex variants")
    func curatedSetContainsComplexVariants() {
        #expect(FloatingPointEquatableTypes.curated.contains("Complex"))
        #expect(FloatingPointEquatableTypes.curated.contains("ComplexModule.Complex"))
    }

    // MARK: - Detector — positive cases

    @Test("isFloatingPointEquatable: Double → true")
    func detectsDouble() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Double"))
    }

    @Test("isFloatingPointEquatable: Float → true")
    func detectsFloat() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Float"))
    }

    @Test("isFloatingPointEquatable: Complex → true")
    func detectsComplex() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Complex"))
    }

    @Test("isFloatingPointEquatable: Complex<Double> → true (generic-stripped)")
    func detectsComplexDouble() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Complex<Double>"))
    }

    @Test("isFloatingPointEquatable: Complex<RealType> → true (generic-stripped)")
    func detectsComplexRealType() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Complex<RealType>"))
    }

    @Test("isFloatingPointEquatable: ComplexModule.Complex<Double> → true")
    func detectsQualifiedComplex() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "ComplexModule.Complex<Double>"))
    }

    @Test("isFloatingPointEquatable: whitespace-padded Double → true")
    func detectsWithWhitespace() {
        #expect(FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "  Double  "))
    }

    // MARK: - Detector — negative cases

    @Test("isFloatingPointEquatable: Int → false")
    func rejectsInt() {
        #expect(!FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Int"))
    }

    @Test("isFloatingPointEquatable: String → false")
    func rejectsString() {
        #expect(!FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "String"))
    }

    @Test("isFloatingPointEquatable: custom user type → false")
    func rejectsUserType() {
        #expect(!FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Money"))
        #expect(!FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "MyWrapper<Double>"))
    }

    @Test("isFloatingPointEquatable: Double? → false (optional out of scope)")
    func rejectsOptionalDouble() {
        #expect(!FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: "Double?"))
    }

    @Test("isFloatingPointEquatable: empty string → false")
    func rejectsEmpty() {
        #expect(!FloatingPointEquatableTypes.isFloatingPointEquatable(typeText: ""))
    }

    // MARK: - Generic-parameter stripping

    @Test("stripGenericParameters: bare type returns unchanged")
    func stripUnchanged() {
        #expect(FloatingPointEquatableTypes.stripGenericParameters("Double") == "Double")
        #expect(FloatingPointEquatableTypes.stripGenericParameters("Complex") == "Complex")
    }

    @Test("stripGenericParameters: removes balanced <...>")
    func stripGenericPair() {
        #expect(FloatingPointEquatableTypes.stripGenericParameters("Complex<Double>") == "Complex")
        #expect(FloatingPointEquatableTypes.stripGenericParameters("Array<Int>") == "Array")
        #expect(FloatingPointEquatableTypes.stripGenericParameters("Dictionary<String, Int>") == "Dictionary")
    }

    @Test("stripGenericParameters: unbalanced angle returns unchanged")
    func stripUnbalanced() {
        // No closing `>` — return verbatim (defensive: user code might
        // contain comparison operators in synthesized type text).
        #expect(FloatingPointEquatableTypes.stripGenericParameters("Foo<Bar") == "Foo<Bar")
    }
}
