import ProtoLawCore
import Testing
@testable import SwiftInferCore

@Suite("TypeShapeBuilder — TypeDecl → ProtoLawCore.TypeShape fold (M4.1)")
struct TypeShapeBuilderTests {

    private func decl(
        _ name: String,
        _ kind: TypeDecl.Kind = .struct,
        file: String = "A.swift",
        line: Int = 1,
        inherits: [String] = [],
        hasUserGen: Bool = false,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inherits,
            location: SourceLocation(file: file, line: line, column: 1),
            hasUserGen: hasUserGen,
            storedMembers: storedMembers,
            hasUserInit: hasUserInit
        )
    }

    // MARK: - Empty + single-decl base cases

    @Test
    func emptyInputProducesEmptyOutput() {
        #expect(TypeShapeBuilder.shapes(from: []).isEmpty)
    }

    @Test
    func singleStructDeclMapsAllFieldsThrough() throws {
        let widget = decl(
            "Widget",
            inherits: ["Equatable"],
            hasUserGen: true,
            storedMembers: [StoredMember(name: "id", typeName: "Int")],
            hasUserInit: false
        )
        let shapes = TypeShapeBuilder.shapes(from: [widget])
        let shape = try #require(shapes.first)
        #expect(shape.name == "Widget")
        #expect(shape.kind == .struct)
        #expect(shape.inheritedTypes == ["Equatable"])
        #expect(shape.hasUserGen == true)
        #expect(shape.storedMembers == [StoredMember(name: "id", typeName: "Int")])
        #expect(shape.hasUserInit == false)
    }

    // MARK: - Kind mapping

    @Test
    func eachPrimaryKindMapsToCorrespondingTypeShapeKind() {
        let decls = [
            decl("S", .struct),
            decl("C", .class),
            decl("E", .enum),
            decl("A", .actor)
        ]
        let shapes = TypeShapeBuilder.shapes(from: decls)
        // shapes() sorts by name; ascending: A, C, E, S.
        #expect(shapes.map(\.name) == ["A", "C", "E", "S"])
        #expect(shapes.map(\.kind) == [.actor, .class, .enum, .struct])
    }

    @Test
    func extensionOnlyRecordsAreSkippedFromShapeOutput() {
        // No primary decl → no `TypeShape.Kind` to assign → shape skipped.
        // The M3.3 EquatableResolver still classifies via raw TypeDecls;
        // this only constrains the M4.2 generator-selection input.
        let decls = [decl("ThirdParty", .extension, inherits: ["Equatable"])]
        #expect(TypeShapeBuilder.shapes(from: decls).isEmpty)
    }

    // MARK: - Same-file extension fold

    @Test
    func sameFileExtensionMergesInheritedTypesIntoPrimaryShape() throws {
        let primary = decl("Foo", .struct, file: "Foo.swift", inherits: ["Equatable"])
        let extn = decl("Foo", .extension, file: "Foo.swift", inherits: ["Hashable"])
        let shape = try #require(TypeShapeBuilder.shapes(from: [primary, extn]).first)
        #expect(shape.inheritedTypes == ["Equatable", "Hashable"])
    }

    @Test
    func sameFileExtensionFlipsHasUserGenOnTheShape() throws {
        let primary = decl("Foo", .struct, file: "Foo.swift", hasUserGen: false)
        let extn = decl("Foo", .extension, file: "Foo.swift", hasUserGen: true)
        let shape = try #require(TypeShapeBuilder.shapes(from: [primary, extn]).first)
        #expect(shape.hasUserGen == true)
    }

    @Test
    func crossFileExtensionDoesNotContributeInheritedTypes() throws {
        // Open decision #1 default — same-file only. An extension in
        // Foo+Hashable.swift doesn't merge into the primary shape's
        // inheritance even though M3.3's EquatableResolver does fold
        // it (resolver runs against raw TypeDecls, not TypeShapes).
        let primary = decl("Foo", .struct, file: "Foo.swift", inherits: ["Equatable"])
        let crossFile = decl("Foo", .extension, file: "Foo+Hashable.swift", inherits: ["Hashable"])
        let shape = try #require(TypeShapeBuilder.shapes(from: [primary, crossFile]).first)
        #expect(shape.inheritedTypes == ["Equatable"])
        #expect(shape.hasUserGen == false)
    }

    @Test
    func crossFileExtensionDoesNotFlipHasUserGen() throws {
        let primary = decl("Foo", .struct, file: "Foo.swift", hasUserGen: false)
        let crossFile = decl("Foo", .extension, file: "Foo+Generators.swift", hasUserGen: true)
        let shape = try #require(TypeShapeBuilder.shapes(from: [primary, crossFile]).first)
        #expect(shape.hasUserGen == false)
    }

    // MARK: - Stored members + hasUserInit are primary-only

    @Test
    func storedMembersComeFromPrimaryDeclOnly() throws {
        // Even if an extension somehow carried a stored-member record
        // (it can't compile in real source, but the data model permits
        // it), the builder reads only the primary's storedMembers.
        let primary = decl(
            "Wallet",
            .struct,
            storedMembers: [StoredMember(name: "balance", typeName: "Int")]
        )
        let extn = decl(
            "Wallet",
            .extension,
            storedMembers: [StoredMember(name: "ghost", typeName: "String")]
        )
        let shape = try #require(TypeShapeBuilder.shapes(from: [primary, extn]).first)
        #expect(shape.storedMembers == [StoredMember(name: "balance", typeName: "Int")])
    }

    @Test
    func hasUserInitComesFromPrimaryDeclOnly() throws {
        // Extensions never set hasUserInit on their TypeDecl record
        // (the scanner enforces this), but the builder also reads only
        // the primary's value defensively in case data flows in from
        // elsewhere.
        let primary = decl("Foo", .struct, hasUserInit: true)
        let extn = decl("Foo", .extension, hasUserInit: true)
        let shape = try #require(TypeShapeBuilder.shapes(from: [primary, extn]).first)
        #expect(shape.hasUserInit == true)
    }

    // MARK: - Determinism

    @Test
    func outputIsSortedByName() {
        let decls = [decl("Zeta"), decl("Alpha"), decl("Mu")]
        let names = TypeShapeBuilder.shapes(from: decls).map(\.name)
        #expect(names == ["Alpha", "Mu", "Zeta"])
    }

    // MARK: - End-to-end via FunctionScanner

    @Test
    func builtFromScannerOutputProducesStrategistInputForMemberwiseDerivation() throws {
        // End-to-end check: scan a tiny corpus, fold to TypeShapes, and
        // confirm the strategist returns .memberwiseArbitrary for a
        // 2-stdlib-member struct without an init or `gen()`.
        let source = """
        struct Money {
            let amount: Int
            let currency: String
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Money.swift")
        let shape = try #require(TypeShapeBuilder.shapes(from: corpus.typeDecls).first)
        let strategy = DerivationStrategist.strategy(for: shape)
        guard case let .memberwiseArbitrary(members) = strategy else {
            Issue.record("Expected .memberwiseArbitrary, got \(strategy)")
            return
        }
        #expect(members.map(\.name) == ["amount", "currency"])
        #expect(members.map(\.rawType) == [.int, .string])
    }

    @Test
    func builtFromScannerOutputProducesUserGenWhenStaticGenIsDeclared() throws {
        let source = """
        struct Widget {
            let id: Int
            static func gen() -> Gen<Widget> { Gen.always(Widget(id: 0)) }
        }
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Widget.swift")
        let shape = try #require(TypeShapeBuilder.shapes(from: corpus.typeDecls).first)
        #expect(DerivationStrategist.strategy(for: shape) == .userGen)
    }
}
