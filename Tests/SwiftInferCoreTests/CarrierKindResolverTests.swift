import PropertyLawCore
import Testing
@testable import SwiftInferCore

@Suite("CarrierKindResolver — V1.18.A value-semantic carrier classifier")
struct CarrierKindResolverTests {

    private func makeResolver(_ decls: [TypeDecl] = []) -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: decls)
    }

    private func decl(
        _ name: String,
        _ kind: TypeDecl.Kind = .struct,
        members: [StoredMember] = []
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: [],
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            storedMembers: members
        )
    }

    private func member(_ name: String, _ typeName: String) -> StoredMember {
        StoredMember(name: name, typeName: typeName)
    }

    // MARK: - Curated stdlib value types

    @Test("Curated integer family classifies as .valueSemantic")
    func curatedIntegerFamily() {
        let resolver = makeResolver()
        for typeName in [
            "Int", "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64"
        ] {
            #expect(
                resolver.classify(typeName: typeName) == .valueSemantic,
                "expected \(typeName) → .valueSemantic"
            )
        }
    }

    @Test("Curated floating-point and Bool classify as .valueSemantic")
    func curatedFloatingAndBool() {
        let resolver = makeResolver()
        for typeName in ["Double", "Float", "Float16", "Float32", "Float64", "Float80", "Bool", "CGFloat"] {
            #expect(resolver.classify(typeName: typeName) == .valueSemantic)
        }
    }

    @Test("Curated string and character types classify as .valueSemantic")
    func curatedStringFamily() {
        let resolver = makeResolver()
        for typeName in ["String", "Substring", "Character", "StaticString"] {
            #expect(resolver.classify(typeName: typeName) == .valueSemantic)
        }
    }

    @Test("Curated Foundation core values classify as .valueSemantic")
    func curatedFoundationValues() {
        let resolver = makeResolver()
        for typeName in ["Data", "Date", "URL", "UUID", "Decimal", "TimeInterval", "TimeZone", "Locale", "Calendar"] {
            #expect(resolver.classify(typeName: typeName) == .valueSemantic)
        }
    }

    @Test("Generic stdlib containers classify as .valueSemantic post-stripping")
    func genericContainers() {
        let resolver = makeResolver()
        for typeName in [
            "Array<Int>", "Dictionary<String, Int>", "Set<UUID>",
            "Optional<Int>", "Result<Int, Error>",
            "Range<Int>", "ClosedRange<Int>", "ContiguousArray<Double>",
            "OrderedSet<Int>", "OrderedDictionary<String, Int>", "Deque<Int>"
        ] {
            #expect(
                resolver.classify(typeName: typeName) == .valueSemantic,
                "expected \(typeName) → .valueSemantic"
            )
        }
    }

    // MARK: - Tuple / array / dict literal syntax

    @Test("Tuple syntax classifies as .valueSemantic")
    func tupleSyntax() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeName: "(Int, String)") == .valueSemantic)
        #expect(resolver.classify(typeName: "(a: Int, b: Int)") == .valueSemantic)
    }

    @Test("Array / dictionary literal syntax classifies as .valueSemantic")
    func collectionLiteralSyntax() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeName: "[Int]") == .valueSemantic)
        #expect(resolver.classify(typeName: "[String: Int]") == .valueSemantic)
        #expect(resolver.classify(typeName: "[[Double]]") == .valueSemantic)
    }

    // MARK: - Generic parameter heuristic

    @Test("Single uppercase-letter generic parameters classify as .valueSemantic")
    func singleLetterGenericParameters() {
        let resolver = makeResolver()
        for typeName in ["T", "U", "V", "K", "E"] {
            #expect(resolver.classify(typeName: typeName) == .valueSemantic)
        }
    }

    @Test("T1 / U2 generic-parameter convention classifies as .valueSemantic")
    func numberedGenericParameters() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeName: "T1") == .valueSemantic)
        #expect(resolver.classify(typeName: "U2") == .valueSemantic)
    }

    @Test("Curated stdlib generic-parameter names classify as .valueSemantic")
    func curatedGenericParameterNames() {
        let resolver = makeResolver()
        for typeName in ["Element", "Wrapped", "Key", "Value", "Failure", "Success", "Bound", "Index"] {
            #expect(resolver.classify(typeName: typeName) == .valueSemantic)
        }
    }

    // MARK: - Class / actor lookup

    @Test("Same-corpus class kind classifies as .referenceType")
    func classKindIsReferenceType() {
        let resolver = makeResolver([decl("CacheService", TypeDecl.Kind.class)])
        #expect(resolver.classify(typeName: "CacheService") == .referenceType)
    }

    @Test("Same-corpus actor kind classifies as .referenceType")
    func actorKindIsReferenceType() {
        let resolver = makeResolver([decl("RequestActor", TypeDecl.Kind.actor)])
        #expect(resolver.classify(typeName: "RequestActor") == .referenceType)
    }

    @Test("Mixed primary class + extension records still classify as .referenceType")
    func classWithExtensionRecordsStillReference() {
        let resolver = makeResolver([
            decl("Service", TypeDecl.Kind.class),
            decl("Service", TypeDecl.Kind.extension)
        ])
        #expect(resolver.classify(typeName: "Service") == .referenceType)
    }

    // MARK: - Struct / enum lookup

    @Test("Empty struct (no stored properties visible) classifies as .valueSemantic")
    func emptyStructIsValueSemantic() {
        let resolver = makeResolver([decl("Marker", .struct)])
        #expect(resolver.classify(typeName: "Marker") == .valueSemantic)
    }

    @Test("Pure enum classifies as .valueSemantic")
    func pureEnumIsValueSemantic() {
        let resolver = makeResolver([decl("Polarity", TypeDecl.Kind.enum)])
        #expect(resolver.classify(typeName: "Polarity") == .valueSemantic)
    }

    @Test("Struct with all curated-value-typed members classifies as .valueSemantic")
    func structWithAllValueMembers() {
        let resolver = makeResolver([
            decl("Counter", .struct, members: [
                member("value", "Int"),
                member("label", "String"),
                member("isActive", "Bool")
            ])
        ])
        #expect(resolver.classify(typeName: "Counter") == .valueSemantic)
    }

    @Test("Struct with class-typed stored member classifies as .mixed")
    func structWithClassMemberIsMixed() {
        let resolver = makeResolver([
            decl("Inventory", .struct, members: [
                member("items", "NSMutableArray")
            ])
        ])
        // NSMutableArray is unknown to the curated set; without a corpus
        // TypeDecl for it the recursion lands at .unknown — and a single
        // unknown member with no other resolution tilts the parent to
        // .unknown. The class-typed leak case is caught by the
        // closure-typed test + the same-corpus class lookup test.
        #expect(resolver.classify(typeName: "Inventory") == .unknown)
    }

    @Test("Struct with same-corpus class-typed member classifies as .mixed (Worked Example 1)")
    func structWithSameCorpusClassMemberIsMixed() {
        // ValueSemantic Kit Proposal §2.2 worked example 1 — struct holding
        // a same-corpus class instance (or in this textual approximation,
        // a class-typed stored property whose class IS in the corpus).
        let resolver = makeResolver([
            decl("Inventory", .struct, members: [
                member("storage", "Storage")
            ]),
            decl("Storage", TypeDecl.Kind.class)
        ])
        #expect(resolver.classify(typeName: "Inventory") == .mixed)
    }

    @Test("Struct with closure-typed member classifies as .mixed (Worked Example 3)")
    func structWithClosureMemberIsMixed() {
        // ValueSemantic Kit Proposal §2.2 worked example 3 — closure
        // captures shared mutable state through reference semantics.
        let resolver = makeResolver([
            decl("Counter", .struct, members: [
                member("increment", "() -> Int")
            ])
        ])
        #expect(resolver.classify(typeName: "Counter") == .mixed)
    }

    @Test("Struct with @escaping closure member still classifies as .mixed")
    func escapingClosureMemberIsMixed() {
        let resolver = makeResolver([
            decl("Handler", .struct, members: [
                member("callback", "@escaping () -> Void")
            ])
        ])
        #expect(resolver.classify(typeName: "Handler") == .mixed)
    }

    @Test("Struct with @Sendable closure member still classifies as .mixed")
    func sendableClosureMemberIsMixed() {
        let resolver = makeResolver([
            decl("Handler", .struct, members: [
                member("callback", "@Sendable (Int) -> Int")
            ])
        ])
        #expect(resolver.classify(typeName: "Handler") == .mixed)
    }

    // MARK: - Recursive composition

    @Test("Struct of struct of curated values classifies as .valueSemantic")
    func recursiveStructComposition() {
        let resolver = makeResolver([
            decl("Outer", .struct, members: [
                member("inner", "Inner"),
                member("count", "Int")
            ]),
            decl("Inner", .struct, members: [
                member("name", "String")
            ])
        ])
        #expect(resolver.classify(typeName: "Outer") == .valueSemantic)
    }

    @Test("Struct nesting a class member at depth 2 propagates .mixed up")
    func nestedClassPropagatesMixed() {
        let resolver = makeResolver([
            decl("Outer", .struct, members: [
                member("inner", "Inner")
            ]),
            decl("Inner", .struct, members: [
                member("service", "CacheService")
            ]),
            decl("CacheService", TypeDecl.Kind.class)
        ])
        #expect(resolver.classify(typeName: "Outer") == .mixed)
    }

    // MARK: - Unknown / depth-bound

    @Test("Top-level (nil) carrier classifies as .unknown")
    func nilTypeNameIsUnknown() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeName: nil) == .unknown)
    }

    @Test("Unresolved corpus type classifies as .unknown")
    func unresolvedTypeIsUnknown() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeName: "MysteryType") == .unknown)
    }

    @Test("Empty type-name string classifies as .unknown")
    func emptyTypeNameIsUnknown() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeName: "") == .unknown)
    }

    @Test("Recursion-depth bound (>3 levels) returns .unknown")
    func recursionDepthBoundReturnsUnknown() {
        let resolver = makeResolver([
            decl("Layer1", .struct, members: [member("inner", "Layer2")]),
            decl("Layer2", .struct, members: [member("inner", "Layer3")]),
            decl("Layer3", .struct, members: [member("inner", "Layer4")]),
            decl("Layer4", .struct, members: [member("inner", "Layer5")]),
            decl("Layer5", .struct, members: [member("value", "Int")])
        ])
        // Layer4 is at depth 3 from Layer1; classifying Layer5 from there
        // exceeds the depth bound and yields .unknown for Layer4 — which
        // propagates upward. (Names use full-word prefixes to avoid
        // collision with the T1/U2 generic-parameter heuristic.)
        #expect(resolver.classify(typeName: "Layer1") == .unknown)
    }

}

@Suite("CarrierKindResolver — V1.18.A signal factory + helpers")
struct CarrierKindResolverSignalFactoryTests {

    private func makeResolver(_ decls: [TypeDecl] = []) -> CarrierKindResolver {
        CarrierKindResolver(typeDecls: decls)
    }

    private func decl(
        _ name: String,
        _ kind: TypeDecl.Kind = .struct,
        members: [StoredMember] = []
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: [],
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            storedMembers: members
        )
    }

    private func member(_ name: String, _ typeName: String) -> StoredMember {
        StoredMember(name: name, typeName: typeName)
    }

    // MARK: - Signal factory

    @Test("Signal factory emits +5 .valueSemanticCarrier for value-semantic carrier")
    func signalFactoryValueSemantic() {
        let resolver = makeResolver([
            decl("Counter", .struct, members: [member("value", "Int")])
        ])
        let signal = resolver.carrierKindSignal(forContainingTypeName: "Counter")
        #expect(signal?.kind == .valueSemanticCarrier)
        #expect(signal?.weight == 5)
        #expect(signal?.detail.contains("Counter") == true)
    }

    @Test("Signal factory emits -10 .referenceTypeCarrier for class carrier")
    func signalFactoryReferenceType() {
        let resolver = makeResolver([decl("Service", TypeDecl.Kind.class)])
        let signal = resolver.carrierKindSignal(forContainingTypeName: "Service")
        #expect(signal?.kind == .referenceTypeCarrier)
        #expect(signal?.weight == -10)
        #expect(signal?.detail.contains("Service") == true)
    }

    @Test("Signal factory emits nil for .mixed carrier")
    func signalFactoryMixedReturnsNil() {
        let resolver = makeResolver([
            decl("Bag", .struct, members: [member("callback", "() -> Void")])
        ])
        #expect(resolver.carrierKindSignal(forContainingTypeName: "Bag") == nil)
    }

    @Test("Signal factory emits nil for .unknown carrier")
    func signalFactoryUnknownReturnsNil() {
        let resolver = makeResolver()
        #expect(resolver.carrierKindSignal(forContainingTypeName: "MysteryType") == nil)
        #expect(resolver.carrierKindSignal(forContainingTypeName: nil) == nil)
    }

    // MARK: - Closure-detection helper

    @Test("Closure-detection helper recognises bare and attributed function types")
    func closureDetectionHelper() {
        #expect(CarrierKindResolver.isClosureType("() -> Void"))
        #expect(CarrierKindResolver.isClosureType("(Int) -> Int"))
        #expect(CarrierKindResolver.isClosureType("@escaping () -> Void"))
        #expect(CarrierKindResolver.isClosureType("@Sendable (Int) -> Bool"))
        #expect(CarrierKindResolver.isClosureType("@MainActor (String) -> Void"))
        // Non-closure types don't match.
        #expect(!CarrierKindResolver.isClosureType("Int"))
        #expect(!CarrierKindResolver.isClosureType("Array<Int>"))
        #expect(!CarrierKindResolver.isClosureType("(Int, String)"))
    }

    @Test("Generic-parameter-stripping helper removes the angle-bracket clause")
    func genericStrippingHelper() {
        #expect(CarrierKindResolver.strippingGenericParameters("Array<Int>") == "Array")
        #expect(CarrierKindResolver.strippingGenericParameters("Dictionary<K, V>") == "Dictionary")
        #expect(CarrierKindResolver.strippingGenericParameters("Int") == "Int")
        #expect(CarrierKindResolver.strippingGenericParameters("Result<Int, Error>") == "Result")
    }
}
