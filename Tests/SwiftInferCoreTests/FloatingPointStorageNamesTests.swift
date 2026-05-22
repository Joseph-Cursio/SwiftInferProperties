@testable import SwiftInferCore
import Testing

@Suite("FloatingPointStorageNames — V1.4.3 curated FP-storage list")
struct FloatingPointStorageNamesTests {

    @Test("All kit-supported names match contains(_:)")
    func kitSupportedNamesMatch() {
        for name in FloatingPointStorageNames.kitSupportedFloatingPoint {
            #expect(FloatingPointStorageNames.contains(name))
        }
    }

    @Test("All non-kit-supported names match contains(_:)")
    func nonKitSupportedNamesMatch() {
        for name in FloatingPointStorageNames.nonKitSupportedFloatingPoint {
            #expect(FloatingPointStorageNames.contains(name))
        }
    }

    @Test("Non-FP types do not match contains(_:)")
    func nonFloatingPointDoesNotMatch() {
        let nonFP = ["Int", "String", "Bool", "Array", "Dictionary", "MyType", "T"]
        for name in nonFP {
            #expect(!FloatingPointStorageNames.contains(name), "\(name) should not match")
        }
    }

    @Test("isKitSupported distinguishes kit-supported from non-kit-supported")
    func isKitSupportedDistinguishes() {
        #expect(FloatingPointStorageNames.isKitSupported("Float"))
        #expect(FloatingPointStorageNames.isKitSupported("Double"))
        #expect(FloatingPointStorageNames.isKitSupported("CGFloat"))
        #expect(!FloatingPointStorageNames.isKitSupported("Complex"))
        #expect(!FloatingPointStorageNames.isKitSupported("Decimal"))
        #expect(!FloatingPointStorageNames.isKitSupported("Int"))
    }

    @Test("Generic parameters strip before lookup")
    func genericStripping() {
        #expect(FloatingPointStorageNames.strippingGenericParameters("Complex<Double>") == "Complex")
        #expect(FloatingPointStorageNames.strippingGenericParameters("Complex<Float>") == "Complex")
        #expect(FloatingPointStorageNames.strippingGenericParameters("Array<Int>") == "Array")
        #expect(FloatingPointStorageNames.strippingGenericParameters("Foo") == "Foo")
        #expect(FloatingPointStorageNames.strippingGenericParameters("").isEmpty)
    }

    @Test("Generic Complex<...> matches contains(_:)")
    func genericComplexMatches() {
        #expect(FloatingPointStorageNames.contains("Complex<Double>"))
        #expect(FloatingPointStorageNames.contains("Complex<Float>"))
        #expect(FloatingPointStorageNames.contains("Complex<Float80>"))
    }

    @Test("Generic Complex<...> is non-kit-supported")
    func genericComplexIsNonKitSupported() {
        #expect(!FloatingPointStorageNames.isKitSupported("Complex<Double>"))
    }

    @Test("Lists are disjoint")
    func listsAreDisjoint() {
        let intersection = FloatingPointStorageNames.kitSupportedFloatingPoint
            .intersection(FloatingPointStorageNames.nonKitSupportedFloatingPoint)
        #expect(intersection.isEmpty, "kit + non-kit lists must be disjoint, found: \(intersection)")
    }
}
