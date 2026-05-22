@testable import SwiftInferCore
import Testing

// V1.7.1 — stdlib-conformance bake-in tests for `ProtocolCoverageMap`.
// Split out of `ProtocolCoverageMapTests.swift` for the SwiftLint
// 400-line file budget per the V1.5.2/V1.6.1 split precedent.
// Per-protocol coverage tests + lookup-helper edge cases stay in the
// primary file; this file owns only the V1.7.1 bake-in surface.

@Suite("ProtocolCoverageMap — V1.7.1 stdlib-conformance bake-in")
struct ProtocolCoverageMapStdlibBakeInTests {

    // MARK: - Table coverage

    @Test("Stdlib bake-in contains exactly 14 documented type keys")
    func bakeInKeyCount() {
        let expected: Set<String> = [
            // Signed integer family
            "Int", "Int8", "Int16", "Int32", "Int64",
            // Unsigned integer family
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64",
            // Floating-point family
            "Float", "Double",
            // Other primitives
            "Bool", "String"
        ]
        #expect(Set(ProtocolCoverageMap.stdlibConformances.keys) == expected)
        #expect(ProtocolCoverageMap.stdlibConformances.count == 14)
    }

    @Test("Int carries Numeric / AdditiveArithmetic / SignedNumeric / Comparable / Hashable / Codable / Equatable")
    func intConformances() {
        let conformances = ProtocolCoverageMap.stdlibConformances["Int"] ?? []
        // Coverage-table-relevant keys
        #expect(conformances.contains("Equatable"))
        #expect(conformances.contains("Comparable"))
        #expect(conformances.contains("Hashable"))
        #expect(conformances.contains("Codable"))
        #expect(conformances.contains("AdditiveArithmetic"))
        #expect(conformances.contains("Numeric"))
        #expect(conformances.contains("SignedNumeric"))
        // Documentation parents (not in coverage table but documented)
        #expect(conformances.contains("BinaryInteger"))
        #expect(conformances.contains("FixedWidthInteger"))
        #expect(conformances.contains("SignedInteger"))
    }

    @Test("UInt carries unsigned-integer conformance set (no SignedNumeric)")
    func uintConformances() {
        let conformances = ProtocolCoverageMap.stdlibConformances["UInt"] ?? []
        #expect(conformances.contains("Numeric"))
        #expect(conformances.contains("AdditiveArithmetic"))
        #expect(conformances.contains("UnsignedInteger"))
        // Critically: unsigned types do not conform to SignedNumeric
        #expect(!conformances.contains("SignedNumeric"))
        #expect(!conformances.contains("SignedInteger"))
    }

    @Test("Double carries floating-point conformance set including SignedNumeric")
    func doubleConformances() {
        let conformances = ProtocolCoverageMap.stdlibConformances["Double"] ?? []
        #expect(conformances.contains("Equatable"))
        #expect(conformances.contains("Comparable"))
        #expect(conformances.contains("Hashable"))
        #expect(conformances.contains("Codable"))
        #expect(conformances.contains("AdditiveArithmetic"))
        #expect(conformances.contains("Numeric"))
        #expect(conformances.contains("SignedNumeric"))
        #expect(conformances.contains("FloatingPoint"))
        #expect(conformances.contains("BinaryFloatingPoint"))
        // Documentation: Double is not BinaryInteger
        #expect(!conformances.contains("BinaryInteger"))
        #expect(!conformances.contains("FixedWidthInteger"))
    }

    @Test("Bool carries Equatable / Hashable / Codable only")
    func boolConformances() {
        let conformances = ProtocolCoverageMap.stdlibConformances["Bool"] ?? []
        #expect(conformances == ["Equatable", "Hashable", "Codable"])
        // Bool is not Comparable in the stdlib
        #expect(!conformances.contains("Comparable"))
        // Bool is not Numeric / AdditiveArithmetic
        #expect(!conformances.contains("Numeric"))
        #expect(!conformances.contains("AdditiveArithmetic"))
    }

    @Test("String carries Equatable / Comparable / Hashable / Codable")
    func stringConformances() {
        let conformances = ProtocolCoverageMap.stdlibConformances["String"] ?? []
        #expect(conformances == ["Equatable", "Comparable", "Hashable", "Codable"])
        // String is not Numeric
        #expect(!conformances.contains("Numeric"))
        #expect(!conformances.contains("AdditiveArithmetic"))
    }

    @Test("Float80 / Float16 are deliberately excluded (platform-conditional)")
    func platformConditionalTypesExcluded() {
        // Documented v1.7 plan open-decision #2 — defer until cycle-5
        // if a corpus example surfaces.
        #expect(ProtocolCoverageMap.stdlibConformances["Float80"] == nil)
        #expect(ProtocolCoverageMap.stdlibConformances["Float16"] == nil)
    }

    @Test("Generic / conditional-conformance types are deliberately excluded")
    func genericTypesExcluded() {
        // V1.7 plan §"Out of scope" — Optional<T> / Array<T> / Set<T>
        // / Dictionary<K,V> / tuples are conditional on element types
        // and a v1.1 constraint-engine concern.
        #expect(ProtocolCoverageMap.stdlibConformances["Array"] == nil)
        #expect(ProtocolCoverageMap.stdlibConformances["Optional"] == nil)
        #expect(ProtocolCoverageMap.stdlibConformances["Set"] == nil)
        #expect(ProtocolCoverageMap.stdlibConformances["Dictionary"] == nil)
    }

    // MARK: - inheritedTypesIndex(from:) integration

    @Test("inheritedTypesIndex seeds with stdlib bake-in even on empty corpus")
    func emptyCorpusYieldsStdlibIndex() {
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        // All 14 stdlib keys should appear without a single TypeDecl
        #expect(merged["Int"]?.contains("Numeric") == true)
        #expect(merged["Double"]?.contains("BinaryFloatingPoint") == true)
        #expect(merged["Bool"]?.contains("Hashable") == true)
        #expect(merged["String"]?.contains("Comparable") == true)
        #expect(merged.count == 14)
    }

    @Test("Corpus extension on a stdlib type unions with (does not replace) the curated set")
    func corpusExtensionUnionsWithStdlibSet() {
        let intExt = TypeDecl(
            name: "Int",
            kind: .extension,
            inheritedTypes: ["MyCustomProto"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [intExt])
        let intConformances = merged["Int"] ?? []
        // Both the curated stdlib set and the corpus extension's added
        // conformance should be present
        #expect(intConformances.contains("Numeric"))
        #expect(intConformances.contains("AdditiveArithmetic"))
        #expect(intConformances.contains("MyCustomProto"))
    }

    @Test("Non-stdlib corpus types still resolve correctly alongside the bake-in")
    func nonStdlibTypesUnaffected() {
        let money = TypeDecl(
            name: "Money",
            kind: .struct,
            inheritedTypes: ["AdditiveArithmetic"],
            location: SourceLocation(file: "A.swift", line: 1, column: 1)
        )
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [money])
        // Corpus type works as before
        #expect(merged["Money"] == ["AdditiveArithmetic"])
        // Stdlib types still appear too
        #expect(merged["Int"]?.contains("AdditiveArithmetic") == true)
    }

    // MARK: - coverageVetoSignal end-to-end

    @Test("coverageVetoSignal fires for Int-typed additive op via the bake-in")
    func coverageVetoFiresForIntAdditive() {
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        let veto = ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: "Int",
            inheritedTypesByName: merged,
            candidateProperties: [.additiveCommutative]
        )
        #expect(veto != nil)
        #expect(veto?.kind == .protocolCoveredProperty)
        #expect(veto?.detail.contains("AdditiveArithmetic") == true
                || veto?.detail.contains("Numeric") == true)
    }

    @Test("coverageVetoSignal fires for Double-typed multiplicative op via the bake-in")
    func coverageVetoFiresForDoubleMultiplicative() {
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        let veto = ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: "Double",
            inheritedTypesByName: merged,
            candidateProperties: [.multiplicativeCommutative]
        )
        #expect(veto != nil)
        #expect(veto?.detail.contains("Numeric") == true)
    }

    @Test("coverageVetoSignal does NOT fire for Bool + additiveCommutative (Bool is not Numeric)")
    func coverageVetoSkipsBoolForAdditive() {
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        let veto = ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: "Bool",
            inheritedTypesByName: merged,
            candidateProperties: [.additiveCommutative]
        )
        #expect(veto == nil)
    }

    @Test("coverageVetoSignal fires for String-typed equatableReflexive via the bake-in")
    func coverageVetoFiresForStringEquatable() {
        let merged = ProtocolCoverageMap.inheritedTypesIndex(from: [])
        let veto = ProtocolCoverageMap.coverageVetoSignal(
            forTypeText: "String",
            inheritedTypesByName: merged,
            candidateProperties: [.equatableReflexive]
        )
        #expect(veto != nil)
    }
}
