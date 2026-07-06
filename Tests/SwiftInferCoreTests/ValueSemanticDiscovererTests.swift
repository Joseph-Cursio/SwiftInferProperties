import PropertyLawCore
@testable import SwiftInferCore
import Testing

/// Slice 2 (recognition) tests for `ValueSemanticDiscoverer`. Hand-built
/// `TypeDecl`s + `FunctionSummary`s exercise the reference-backed candidate
/// signal and its precision guards (pure-value struct / class / unknown member
/// / no mutation surface excluded).
struct ValueSemanticDiscovererTests {

    // MARK: - Recognition

    @Test func recognizesReferenceContainerStruct() throws {
        // struct Inventory { var items: NSMutableArray }; func add(_:) -> Void
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [structDecl("Inventory", members: [("items", "NSMutableArray")])],
            functions: [method("add", on: "Inventory", params: 1)]  // non-mutating, Void
        )
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(candidate.typeName == "Inventory")
        #expect(candidate.referenceBackedMembers.map(\.kind) == [.referenceContainer])
        #expect(candidate.mutationSurface.map(\.name) == ["add"])
        // The leak method is NOT `mutating` — captured anyway (Example-1 shape).
        #expect(candidate.mutationSurface.first?.isMutating == false)
    }

    @Test func recognizesCorpusClassBackedStruct() {
        // struct Badge { var box: Box }  where `class Box`
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [
                structDecl("Badge", members: [("box", "Box")]),
                classDecl("Box")
            ],
            functions: [method("increment", on: "Badge", mutating: true)]
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.referenceBackedMembers.map(\.kind) == [.corpusReference])
    }

    @Test func recognizesClosureBackedStruct() {
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [structDecl("Counter", members: [("increment", "() -> Int")])],
            functions: [method("tick", on: "Counter", mutating: true)]
        )
        #expect(candidates.count == 1)
        #expect(candidates.first?.referenceBackedMembers.map(\.kind) == [.closure])
    }

    @Test func stripsOptionalAndAttributesWhenClassifying() throws {
        // `Box?` resolves to the corpus class; `@escaping () -> Void` is a closure.
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [
                structDecl("Both", members: [("box", "Box?"), ("onChange", "@escaping () -> Void")]),
                classDecl("Box")
            ],
            functions: [method("mutate", on: "Both", mutating: true)]
        )
        let candidate = try #require(candidates.first)
        #expect(candidate.referenceBackedMembers.map(\.kind) == [.corpusReference, .closure])
    }

    // MARK: - Precision guards

    @Test func excludesPureValueStruct() {
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [structDecl("Point", members: [("x", "Int"), ("y", "Double")])],
            functions: [method("translate", on: "Point", mutating: true)]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesClassAndActor() {
        // A class holding a reference member is NOT a value-semantics candidate.
        let refHolder = TypeDecl(
            name: "RefHolder",
            kind: .class,
            inheritedTypes: [],
            location: loc(),
            storedMembers: [StoredMember(name: "box", typeName: "Box")]
        )
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [refHolder, classDecl("Box")],
            functions: [method("mutate", on: "RefHolder", mutating: true)]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesUnknownExternalMember() {
        // `Widget` is not in the corpus, not a curated container, not a closure
        // → conservatively not reference-backed.
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [structDecl("Wrapper", members: [("widget", "Widget")])],
            functions: [method("mutate", on: "Wrapper", mutating: true)]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesStructWithoutMutationSurface() {
        // Reference-backed, but only a query (non-mutating, non-Void) and a
        // static method → nothing to test.
        let candidates = ValueSemanticDiscoverer.discover(
            typeDecls: [structDecl("Cache", members: [("store", "NSCache")])],
            functions: [
                method("count", on: "Cache", returns: "Int"),      // query → excluded
                method("make", on: "Cache", isStatic: true)        // static → excluded
            ]
        )
        #expect(candidates.isEmpty)
    }

    // MARK: - Mutation surface shape

    @Test func mutationSurfaceIncludesMutatingAndVoidExcludesQueries() {
        let surface = ValueSemanticDiscoverer.mutationSurface(
            of: "Buffer",
            functions: [
                method("append", on: "Buffer", mutating: true, params: 1),   // include
                method("flush", on: "Buffer"),                                // Void, non-mutating → include
                method("bytes", on: "Buffer", returns: "[UInt8]"),            // query → exclude
                method("empty", on: "Buffer", isStatic: true),               // static → exclude
                method("append", on: "Other", mutating: true)                // wrong type → exclude
            ]
        )
        #expect(surface.map(\.name) == ["append", "flush"])
    }

    @Test func mutationSurfaceMergesExtensionMethodsAcrossFiles() {
        // Methods in an extension (different file) share `containingTypeName`.
        let surface = ValueSemanticDiscoverer.mutationSurface(
            of: "Doc",
            functions: [
                method("edit", on: "Doc", mutating: true, params: 1, file: "Doc.swift"),
                method("clear", on: "Doc", mutating: true, file: "Doc+Editing.swift")
            ]
        )
        #expect(surface.map(\.name) == ["clear", "edit"])
    }
}

// MARK: - Builders

private func loc(_ line: Int = 1, _ file: String = "F.swift") -> SwiftInferCore.SourceLocation {
    SwiftInferCore.SourceLocation(file: file, line: line, column: 1)
}

private func structDecl(
    _ name: String,
    members: [(String, String)],
    line: Int = 1,
    file: String = "F.swift"
) -> TypeDecl {
    TypeDecl(
        name: name,
        kind: .struct,
        inheritedTypes: [],
        location: loc(line, file),
        storedMembers: members.map { StoredMember(name: $0.0, typeName: $0.1) }
    )
}

private func classDecl(_ name: String) -> TypeDecl {
    TypeDecl(name: name, kind: .class, inheritedTypes: [], location: loc())
}

private func method(
    _ name: String,
    on containingType: String,
    mutating: Bool = false,
    returns: String? = nil,
    params: Int = 0,
    isStatic: Bool = false,
    file: String = "F.swift"
) -> FunctionSummary {
    FunctionSummary(
        name: name,
        parameters: (0..<params).map { index in
            Parameter(label: nil, internalName: "arg\(index)", typeText: "Int", isInout: false)
        },
        returnTypeText: returns,
        isThrows: false,
        isAsync: false,
        isMutating: mutating,
        isStatic: isStatic,
        location: loc(1, file),
        containingTypeName: containingType,
        bodySignals: .empty
    )
}
