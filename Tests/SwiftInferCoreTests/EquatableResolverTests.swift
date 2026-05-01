import Testing
@testable import SwiftInferCore

@Suite("EquatableResolver — three-valued textual classifier (M3.3)")
struct EquatableResolverTests {

    private func makeResolver(_ decls: [TypeDecl] = []) -> EquatableResolver {
        EquatableResolver(typeDecls: decls)
    }

    private func decl(
        _ name: String,
        _ kind: TypeDecl.Kind = .struct,
        inherits: [String] = []
    ) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inherits,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1)
        )
    }

    // MARK: Curated stdlib equatable

    @Test
    func curatedStdlibScalarsClassifyAsEquatable() {
        let resolver = makeResolver()
        for typeText in ["Int", "String", "Bool", "Double", "Float", "UUID", "Date", "URL"] {
            #expect(resolver.classify(typeText: typeText) == .equatable, "expected \(typeText) → .equatable")
        }
    }

    @Test
    func fixedWidthIntegerFamilyClassifiesAsEquatable() {
        let resolver = makeResolver()
        for typeText in [
            "Int8", "Int16", "Int32", "Int64",
            "UInt", "UInt8", "UInt16", "UInt32", "UInt64"
        ] {
            #expect(resolver.classify(typeText: typeText) == .equatable, "expected \(typeText) → .equatable")
        }
    }

    @Test
    func leadingAndTrailingWhitespaceIsTrimmedBeforeMatching() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "  Int  ") == .equatable)
        #expect(resolver.classify(typeText: "\tString\n") == .equatable)
    }

    // MARK: Curated non-equatable shapes

    @Test
    func anyAndAnyObjectClassifyAsNotEquatable() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "Any") == .notEquatable)
        #expect(resolver.classify(typeText: "AnyObject") == .notEquatable)
    }

    @Test
    func functionTypesClassifyAsNotEquatable() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "(Int) -> Int") == .notEquatable)
        #expect(resolver.classify(typeText: "() -> Void") == .notEquatable)
        #expect(resolver.classify(typeText: "(String, Int) -> Bool") == .notEquatable)
        // Function type nested inside a generic is still detected — `->`
        // is unambiguous because Swift type syntax uses `<>` for generics
        // and `(,)` for tuples.
        #expect(resolver.classify(typeText: "[(Int) -> Int]") == .notEquatable)
        #expect(resolver.classify(typeText: "Array<(Int) -> Int>") == .notEquatable)
    }

    @Test
    func opaqueAndExistentialPrefixesClassifyAsNotEquatable() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "some Hashable") == .notEquatable)
        #expect(resolver.classify(typeText: "any Hashable") == .notEquatable)
        #expect(resolver.classify(typeText: "some Collection") == .notEquatable)
        #expect(resolver.classify(typeText: "any Error") == .notEquatable)
    }

    @Test
    func bareSomeOrAnyIdentifierIsNotMisclassified() {
        // `someType` and `anyValue` are user-named identifiers, not the
        // `some Foo` / `any Foo` prefix. The detector requires the trailing
        // space — `someType` does not match `"some "`.
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "someType") == .unknown)
        #expect(resolver.classify(typeText: "anyValue") == .unknown)
    }

    // MARK: Corpus-derived equatable

    @Test
    func corpusTypeDeclaringEquatableLiftsToEquatable() {
        let resolver = makeResolver([decl("Token", inherits: ["Equatable"])])
        #expect(resolver.classify(typeText: "Token") == .equatable)
    }

    @Test
    func corpusTypeDeclaringHashableLiftsToEquatableViaKnownConformance() {
        // Hashable refines Equatable in the standard library — corpus
        // types that conform to Hashable are also Equatable.
        let resolver = makeResolver([decl("Identifier", inherits: ["Hashable"])])
        #expect(resolver.classify(typeText: "Identifier") == .equatable)
    }

    @Test
    func corpusTypeDeclaringComparableLiftsToEquatableViaKnownConformance() {
        let resolver = makeResolver([decl("Version", inherits: ["Comparable"])])
        #expect(resolver.classify(typeText: "Version") == .equatable)
    }

    @Test
    func corpusTypeWithNoRelevantInheritanceIsUnknown() {
        // Inheritance carries an unrelated protocol — no signal either way.
        let resolver = makeResolver([decl("Logger", inherits: ["CustomStringConvertible"])])
        #expect(resolver.classify(typeText: "Logger") == .unknown)
    }

    @Test
    func corpusTypeWithoutAnyInheritanceIsUnknown() {
        let resolver = makeResolver([decl("Bare")])
        #expect(resolver.classify(typeText: "Bare") == .unknown)
    }

    @Test
    func extensionAddingEquatableLiftsPrimaryDecl() {
        // Open decision #2 contract: a primary decl + an extension that
        // adds Equatable both keyed under `name` — the resolver merges so
        // the type classifies as .equatable.
        let resolver = makeResolver([
            decl("Foo", .struct, inherits: []),
            decl("Foo", .extension, inherits: ["Equatable"])
        ])
        #expect(resolver.classify(typeText: "Foo") == .equatable)
    }

    @Test
    func extensionOnlyDeclWithEquatableStillClassifiesAsEquatable() {
        // No primary record (the type is declared in another module),
        // only the extension. Resolver should still classify .equatable.
        let resolver = makeResolver([decl("ThirdParty", .extension, inherits: ["Equatable"])])
        #expect(resolver.classify(typeText: "ThirdParty") == .equatable)
    }

    @Test
    func multipleEquatableEvidenceRecordsForSameNameStayEquatable() {
        // Two extensions in two files both adding Equatable shouldn't
        // confuse the merge — set semantics make this idempotent.
        let resolver = makeResolver([
            decl("Bar", .extension, inherits: ["Equatable"]),
            decl("Bar", .extension, inherits: ["Equatable"])
        ])
        #expect(resolver.classify(typeText: "Bar") == .equatable)
    }

    @Test
    func mixedConformanceListPicksUpEquatableAlongsideOthers() {
        // Inheritance carries multiple protocols; one of them is Hashable.
        let resolver = makeResolver([decl("Token", inherits: ["CustomStringConvertible", "Hashable", "Sendable"])])
        #expect(resolver.classify(typeText: "Token") == .equatable)
    }

    // MARK: Unknown — three-state correctness

    @Test
    func unknownTypeNameWithNoCorpusMatchIsUnknown() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "Mystery") == .unknown)
    }

    @Test
    func genericContainerOfEquatableScalarStaysUnknown() {
        // Open decision: conditional conformance reasoning is v1.1.
        // Array<Int> IS Equatable, but the textual resolver doesn't
        // unfold conditional conformances.
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "Array<Int>") == .unknown)
        #expect(resolver.classify(typeText: "[Int]") == .unknown)
        #expect(resolver.classify(typeText: "Optional<Int>") == .unknown)
        #expect(resolver.classify(typeText: "Int?") == .unknown)
    }

    @Test
    func tupleOfEquatableStaysUnknown() {
        // Tuple Equatable is conditional; out of M3 scope.
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "(Int, String)") == .unknown)
    }

    @Test
    func nonEquatableShapeWinsOverCuratedStdlibName() {
        // Defensive check: the non-Equatable detector is consulted first,
        // so even an "Int"-bearing function type classifies as
        // .notEquatable rather than accidentally matching the stdlib set.
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "(Int) -> Int") == .notEquatable)
    }

    // MARK: Integration — built from a real ScannedCorpus

    @Test
    func resolverBuiltFromScannedCorpusClassifiesEquatableAndUnknown() {
        let source = """
        struct EqType: Equatable {
            let n: Int
        }
        struct PlainType {
            let n: Int
        }
        extension Foo: Hashable {}
        """
        let corpus = FunctionScanner.scanCorpus(source: source, file: "Test.swift")
        let resolver = EquatableResolver(typeDecls: corpus.typeDecls)
        #expect(resolver.classify(typeText: "EqType") == .equatable)
        #expect(resolver.classify(typeText: "PlainType") == .unknown)
        #expect(resolver.classify(typeText: "Foo") == .equatable)
        #expect(resolver.classify(typeText: "Int") == .equatable)
        #expect(resolver.classify(typeText: "Mystery") == .unknown)
        #expect(resolver.classify(typeText: "(Int) -> Int") == .notEquatable)
    }
}
