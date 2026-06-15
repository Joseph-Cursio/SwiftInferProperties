import PropertyLawCore
@testable import SwiftInferCore
import Testing

/// Cycle 139 — unit tests for the textual `Identifiable` classifier that
/// gates the referential-integrity verify path. Pure, no disk.
@Suite("IdentifiableResolver — three-valued textual classifier (cycle 139)")
struct IdentifiableResolverTests {

    private func decl(
        _ name: String,
        _ kind: TypeDecl.Kind = .struct,
        inherits: [String] = [],
        members: [StoredMember] = []
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inherits,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            storedMembers: members
        )
    }

    private func member(_ name: String, _ type: String = "Int") -> StoredMember {
        StoredMember(name: name, typeName: type)
    }

    @Test("a corpus type declaring Identifiable → .identifiable")
    func identifiableConformanceLifts() {
        let resolver = IdentifiableResolver(typeDecls: [decl("Book", inherits: ["Equatable", "Identifiable"])])
        #expect(resolver.classify(typeText: "Book") == .identifiable)
    }

    @Test("a corpus type with a stored id member (no formal conformance) → .identifiable")
    func storedIDMemberLifts() {
        let resolver = IdentifiableResolver(typeDecls: [
            decl("Row", inherits: ["Equatable"], members: [member("id"), member("title", "String")])
        ])
        #expect(resolver.classify(typeText: "Row") == .identifiable)
    }

    @Test("Identifiable added via a separate extension lifts the type (merge by name)")
    func extensionConformanceLifts() {
        let resolver = IdentifiableResolver(typeDecls: [
            decl("Item", members: [member("name", "String")]),
            decl("Item", .extension, inherits: ["Identifiable"])
        ])
        #expect(resolver.classify(typeText: "Item") == .identifiable)
    }

    @Test("a seen corpus type with neither conformance nor id member → .notIdentifiable")
    func seenButNonIdentifiable() {
        let resolver = IdentifiableResolver(typeDecls: [
            decl("Note", inherits: ["Equatable"], members: [member("text", "String")])
        ])
        #expect(resolver.classify(typeText: "Note") == .notIdentifiable)
    }

    @Test("a type not declared in the corpus (external) → .unknown")
    func unseenTypeIsUnknown() {
        let resolver = IdentifiableResolver(typeDecls: [decl("Book", inherits: ["Identifiable"])])
        #expect(resolver.classify(typeText: "RemoteModel") == .unknown)
        // The gate proceeds (builds) on .unknown, so an external Identifiable
        // dependency type is never wrongly skipped.
    }

    @Test("classification trims whitespace")
    func trimsWhitespace() {
        let resolver = IdentifiableResolver(typeDecls: [decl("Book", inherits: ["Identifiable"])])
        #expect(resolver.classify(typeText: "  Book  ") == .identifiable)
    }
}
