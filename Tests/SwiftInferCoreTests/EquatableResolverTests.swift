@testable import SwiftInferCore
import Testing

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
        for typeText in ["Int", "String", "Bool", "Double", "Float", "UUID", "Date", "URL", "Data"] {
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

    // MARK: Array / Optional payload rewrite

    /// `Array` and `Optional` conform to `Equatable` under exactly one
    /// condition — their single payload does — so the container inherits the
    /// payload's verdict. This is a rewrite, not the general conditional-
    /// conformance reasoning PRD §20.2 still defers.
    ///
    /// This test previously asserted `.unknown` for all four, with a comment
    /// conceding "Array<Int> IS Equatable". That concession had a measured
    /// cost: `[String]` and `URL?` carriers were demoted out of
    /// `RoundTripTemplate` into the weaker inverse-pair tier — the same failure
    /// mode that put `Data` in `curatedEquatableStdlib` by hand.
    @Test
    func arrayAndOptionalInheritTheirPayloadVerdict() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "Array<Int>") == .equatable)
        #expect(resolver.classify(typeText: "[Int]") == .equatable)
        #expect(resolver.classify(typeText: "Optional<Int>") == .equatable)
        #expect(resolver.classify(typeText: "Int?") == .equatable)
        #expect(resolver.classify(typeText: "Int!") == .equatable)
    }

    /// An unknown payload leaves the container unknown — the rewrite forwards
    /// the verdict, it does not manufacture one.
    @Test
    func containerOfUnknownPayloadStaysUnknown() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "[Mystery]") == .unknown)
        #expect(resolver.classify(typeText: "Mystery?") == .unknown)
    }

    /// `.notEquatable` forwards too, and the curated non-Equatable detector is
    /// consulted *before* the rewrite — so `[Any]` refutes rather than
    /// unwrapping to a bare `Any` and then refuting for a different reason.
    @Test
    func containerOfNonEquatablePayloadRefutes() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "[Any]") == .notEquatable)
        #expect(resolver.classify(typeText: "[(Int) -> Int]") == .notEquatable)
        #expect(resolver.classify(typeText: "AnyObject?") == .notEquatable)
    }

    /// Nesting falls out of the rewrite because each step shortens the text.
    @Test
    func nestedContainersUnwrapRepeatedly() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "[String?]") == .equatable)
        #expect(resolver.classify(typeText: "[[Int]]") == .equatable)
        #expect(resolver.classify(typeText: "[Int]?") == .equatable)
    }

    /// A corpus-declared `Equatable` type lifts its containers too — this is
    /// what makes `[Suggestion]` classify, not just the curated stdlib names.
    @Test
    func corpusEquatableTypeLiftsItsContainers() {
        let resolver = makeResolver([decl("Blob", inherits: ["Equatable"])])
        #expect(resolver.classify(typeText: "Blob") == .equatable)
        #expect(resolver.classify(typeText: "[Blob]") == .equatable)
        #expect(resolver.classify(typeText: "Blob?") == .equatable)
    }

    /// `Set` and `Dictionary` are deliberately excluded: their conformances
    /// rest on different constraints (`Set` needs `Element: Hashable`,
    /// `Dictionary` needs `Value: Equatable`), so they are not a rewrite.
    @Test
    func setAndDictionaryStayUnknown() {
        let resolver = makeResolver()
        #expect(resolver.classify(typeText: "Set<Int>") == .unknown)
        #expect(resolver.classify(typeText: "[String: Int]") == .unknown)
        #expect(resolver.classify(typeText: "Dictionary<String, Int>") == .unknown)
    }

    /// A dictionary nested inside an array must not make the array read as a
    /// dictionary — the colon test tracks bracket depth for exactly this.
    @Test
    func arrayOfDictionariesIsNotMistakenForADictionary() {
        #expect(EquatableResolver.singlePayloadElement(of: "[[String: Int]]") == "[String: Int]")
        #expect(EquatableResolver.singlePayloadElement(of: "[String: Int]") == nil)
    }

    @Test
    func tupleOfEquatableStaysUnknown() {
        // Tuples are not nominal types and cannot conform at all.
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
