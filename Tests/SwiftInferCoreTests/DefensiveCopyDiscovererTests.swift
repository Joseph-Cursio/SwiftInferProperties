@testable import SwiftInferCore
import Testing

/// Slice 6b tests for `DefensiveCopyDiscoverer`. Hand-built `TypeDecl`s +
/// `FunctionSummary`s exercise the class-with-copy-method signal and its
/// precision guards (non-class / no copy method / foreign-return-type excluded).
struct DefensiveCopyDiscovererTests {

    @Test func recognizesClassWithCopyMethod() throws {
        let candidates = DefensiveCopyDiscoverer.discover(
            typeDecls: [classDecl("Buffer", inherited: ["Equatable"])],
            functions: [
                method("copy", on: "Buffer", returns: "Buffer"),
                method("append", on: "Buffer")
            ]
        )
        #expect(candidates.count == 1)
        let candidate = try #require(candidates.first)
        #expect(candidate.copyMethodName == "copy")
        #expect(candidate.mutationSurface.map(\.name) == ["append"])
        #expect(candidate.equatability == .equatable)
    }

    @Test func recognizesCloneVerbAndSelfReturn() {
        let clone = DefensiveCopyDiscoverer.discover(
            typeDecls: [classDecl("A")],
            functions: [method("clone", on: "A", returns: "A"), method("go", on: "A")]
        )
        #expect(clone.first?.copyMethodName == "clone")

        let selfReturn = DefensiveCopyDiscoverer.discover(
            typeDecls: [classDecl("B")],
            functions: [method("copy", on: "B", returns: "Self"), method("go", on: "B")]
        )
        #expect(selfReturn.first?.copyMethodName == "copy")
    }

    @Test func excludesClassWithoutCopyMethod() {
        let candidates = DefensiveCopyDiscoverer.discover(
            typeDecls: [classDecl("Plain")],
            functions: [method("update", on: "Plain")]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesStructWithCopyMethod() {
        let candidates = DefensiveCopyDiscoverer.discover(
            typeDecls: [structDecl("SBox")],
            functions: [method("copy", on: "SBox", returns: "SBox")]
        )
        #expect(candidates.isEmpty)
    }

    @Test func excludesCopyVerbReturningForeignType() {
        // `copy() -> Int` is not a defensive copy of the class.
        let candidates = DefensiveCopyDiscoverer.discover(
            typeDecls: [classDecl("Weird")],
            functions: [method("copy", on: "Weird", returns: "Int"), method("go", on: "Weird")]
        )
        #expect(candidates.isEmpty)
    }

    @Test func mutationSurfaceExcludesCopyAndQueriesAndStatics() {
        let surface = DefensiveCopyDiscoverer.mutationSurface(
            of: "Widget",
            functions: [
                method("mutate", on: "Widget"),                    // Void → include
                method("copy", on: "Widget", returns: "Widget"),   // returns type → exclude
                method("count", on: "Widget", returns: "Int"),     // query → exclude
                method("make", on: "Widget", isStatic: true),      // static → exclude
                method("mutate", on: "Other")                      // wrong type → exclude
            ]
        )
        #expect(surface.map(\.name) == ["mutate"])
    }
}

// MARK: - Builders

private func loc(_ line: Int = 1, _ file: String = "F.swift") -> SwiftInferCore.SourceLocation {
    SwiftInferCore.SourceLocation(file: file, line: line, column: 1)
}

private func classDecl(_ name: String, inherited: [String] = [], line: Int = 1) -> TypeDecl {
    TypeDecl(name: name, kind: .class, inheritedTypes: inherited, location: loc(line))
}

private func structDecl(_ name: String) -> TypeDecl {
    TypeDecl(name: name, kind: .struct, inheritedTypes: [], location: loc())
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
