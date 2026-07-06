@testable import SwiftInferCore
import Testing

/// Slice 6e-b tests for `StableIdentityDiscoverer`. Hand-built `TypeDecl`s +
/// `FunctionSummary`s exercise the Hashable-class-with-mutation signal and its
/// precision guards (non-Hashable / immutable / struct excluded).
struct StableIdentityDiscovererTests {

    @Test func recognizesHashableClassWithMutation() throws {
        let candidates = StableIdentityDiscoverer.discover(
            typeDecls: [classDecl("Node", inherited: ["Hashable"])],
            functions: [method("rename", on: "Node"), method("id", on: "Node", returns: "Int")]
        )
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(candidate.typeName == "Node")
        #expect(candidate.mutationSurface.map(\.name) == ["rename"])  // Void only; `id` query excluded
    }

    @Test func excludesNonHashableClass() {
        let candidates = StableIdentityDiscoverer.discover(
            typeDecls: [classDecl("Plain", inherited: ["Equatable"])],
            functions: [method("mutate", on: "Plain")]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesImmutableHashableClass() {
        // Hashable but no Void mutation method → can't drift → not surfaced.
        let candidates = StableIdentityDiscoverer.discover(
            typeDecls: [classDecl("Frozen", inherited: ["Hashable"])],
            functions: [method("describe", on: "Frozen", returns: "String")]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesHashableStruct() {
        let candidates = StableIdentityDiscoverer.discover(
            typeDecls: [structDecl("Point", inherited: ["Hashable"])],
            functions: [method("shift", on: "Point")]
        )
        #expect(candidates.isEmpty)
    }

    @Test func hashableViaExtensionIsRecognized() {
        // Primary class decl + an extension adding Hashable.
        let candidates = StableIdentityDiscoverer.discover(
            typeDecls: [
                classDecl("Ext", inherited: []),
                TypeDecl(name: "Ext", kind: .extension, inheritedTypes: ["Hashable"], location: loc())
            ],
            functions: [method("touch", on: "Ext")]
        )
        #expect(candidates.first?.typeName == "Ext")
    }
}

// MARK: - Builders

private func loc(_ line: Int = 1, _ file: String = "F.swift") -> SwiftInferCore.SourceLocation {
    SwiftInferCore.SourceLocation(file: file, line: line, column: 1)
}

private func classDecl(_ name: String, inherited: [String], line: Int = 1) -> TypeDecl {
    TypeDecl(name: name, kind: .class, inheritedTypes: inherited, location: loc(line))
}

private func structDecl(_ name: String, inherited: [String]) -> TypeDecl {
    TypeDecl(name: name, kind: .struct, inheritedTypes: inherited, location: loc())
}

private func method(
    _ name: String,
    on containingType: String,
    returns: String? = nil,
    params: Int = 0,
    isStatic: Bool = false
) -> FunctionSummary {
    FunctionSummary(
        name: name,
        parameters: (0..<params).map { index in
            Parameter(label: nil, internalName: "arg\(index)", typeText: "Int", isInout: false)
        },
        returnTypeText: returns,
        isThrows: false,
        isAsync: false,
        isMutating: false,
        isStatic: isStatic,
        location: loc(),
        containingTypeName: containingType,
        bodySignals: .empty
    )
}
