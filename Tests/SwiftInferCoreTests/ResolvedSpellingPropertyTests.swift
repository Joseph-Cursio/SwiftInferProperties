import Foundation
import PropertyLawKit
@testable import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md` §11.1) — the
// consumer-side half of the bare-name collapse.
//
// `TypeShapeBuilder` now keys shapes by qualified name, which fixes the collapse
// but creates a second problem: source writes `kind: Kind` *inside*
// `IndexedTypeShape`, so qualifying the shape names without also qualifying the
// references would leave every nested member unresolvable — trading a wrong
// answer for no answer. `resolvedSpelling` closes that by resolving a member's
// type spelling the way Swift does: innermost enclosing scope first, then
// outward, then file scope.
//
// It is a string rewriter over a type-spelling grammar, which is exactly the
// shape that fails on inputs nobody thought to hand-write. Hence properties
// rather than a handful of examples: the laws below quantify over generated
// spellings and generated universes, and the hand-picked cases that follow pin
// the specific shapes the production index actually contains.
@Suite("Road test — nested type-spelling resolution")
struct ResolvedSpellingPropertyTests {

    // MARK: - Generators

    /// A universe with a nested type under `Outer`, a same-named top-level type,
    /// and decoys whose names *contain* the nested name.
    private static let universe: Set<String> = [
        "Outer",
        "Outer.Kind",
        "Outer.StoredMember",
        "Outer.Inner",
        "Outer.Inner.Kind",
        "Kind",
        "CardinalityFieldKind",
        "KindResolver",
        "String",
        "Wrapper"
    ]

    private static let bareNames = ["Kind", "StoredMember", "Inner", "Wrapper", "Unknown", "String"]

    /// Spelling shapes the real index contains — bare, optional, array,
    /// dictionary, nested collection, generic.
    private static let shapes = [
        "%@", "%@?", "[%@]", "[%@]?", "[String: %@]", "[[%@]]",
        "Array<%@>", "Set<%@>", "%@??", "[%@: %@]"
    ]

    private static let spellingGen = zip(
        Gen.element(of: shapes).map { $0! },
        Gen.element(of: bareNames).map { $0! }
    ).map { shape, name in shape.replacingOccurrences(of: "%@", with: name) }

    private static let enclosingGen = Gen.element(of: ["Outer", "Outer.Inner", "Wrapper", "Elsewhere"])
        .map { $0! }

    // MARK: - Laws

    /// **Idempotence — the load-bearing law.**
    ///
    /// Resolving twice must equal resolving once. If the rewriter matched a bare
    /// `Kind` inside an already-qualified `Outer.Kind`, a second pass would
    /// produce `Outer.Outer.Kind`. That is not hypothetical: the pipeline builds
    /// shapes once, but nothing structurally prevents a caller from re-deriving
    /// from already-resolved spellings, and the failure would be a type name that
    /// looks almost right.
    @Test("resolution is idempotent")
    func resolutionIsIdempotent() async {
        await propertyCheck(input: Self.spellingGen, Self.enclosingGen) { spelling, enclosing in
            let once = TypeShapeBuilder.resolvedSpelling(
                spelling, enclosing: enclosing, universe: Self.universe
            )
            let twice = TypeShapeBuilder.resolvedSpelling(
                once, enclosing: enclosing, universe: Self.universe
            )
            #expect(twice == once, "resolving \(spelling) twice diverged")
        }
    }

    /// The non-identifier structure of a spelling is preserved exactly — every
    /// bracket, colon, angle bracket and `?` survives in the same order. Only
    /// identifiers may change.
    ///
    /// This is what stops the rewriter from being a plausible-looking string
    /// mangler: `[String: Kind]` must come back as `[String: Outer.Kind]`, never
    /// `[String Outer.Kind]` or `[String: Outer.Kind]]`.
    @Test("resolution preserves the spelling's punctuation exactly")
    func resolutionPreservesPunctuation() async {
        let structural = Set("[]<>?:, ")
        await propertyCheck(input: Self.spellingGen, Self.enclosingGen) { spelling, enclosing in
            let resolved = TypeShapeBuilder.resolvedSpelling(
                spelling, enclosing: enclosing, universe: Self.universe
            )
            #expect(
                resolved.filter { structural.contains($0) }
                    == spelling.filter { structural.contains($0) },
                "punctuation changed resolving \(spelling)"
            )
        }
    }

    /// Resolution only ever *qualifies* — the output contains the input's
    /// identifiers as suffixes, never a different name. A rewriter that mapped
    /// `Kind` to some unrelated universe member would satisfy idempotence and
    /// punctuation-preservation while being catastrophically wrong.
    @Test("resolution only qualifies — it never renames")
    func resolutionOnlyQualifies() async {
        await propertyCheck(input: Self.spellingGen, Self.enclosingGen) { spelling, enclosing in
            let resolved = TypeShapeBuilder.resolvedSpelling(
                spelling, enclosing: enclosing, universe: Self.universe
            )
            // Every identifier in the output is either unchanged or the input
            // identifier with a scope prefix.
            for identifier in resolved.split(whereSeparator: { "[]<>?:, ".contains($0) }) {
                let bare = identifier.split(separator: ".").last.map(String.init) ?? ""
                #expect(
                    spelling.contains(bare),
                    "\(identifier) in the output has no counterpart in \(spelling)"
                )
            }
        }
    }

    /// An identifier absent from the universe is returned untouched — external
    /// and stdlib types must pass through. Paired with the law above this bounds
    /// the rewriter from both sides: it qualifies what it knows and nothing else.
    @Test("unknown identifiers are left alone")
    func unknownIdentifiersAreUntouched() async {
        await propertyCheck(input: Gen.element(of: Self.shapes).map { $0! }, Self.enclosingGen) { shape, enclosing in
            let spelling = shape.replacingOccurrences(of: "%@", with: "TotallyExternal")
            #expect(
                TypeShapeBuilder.resolvedSpelling(
                    spelling, enclosing: enclosing, universe: Self.universe
                ) == spelling
            )
        }
    }

    // MARK: - The specific shapes the production index contains

    /// Innermost scope wins. Both `Outer.Inner.Kind` and `Outer.Kind` exist; a
    /// member of `Outer.Inner` spelled `Kind` must resolve to the inner one —
    /// that is Swift's lookup order, and getting it backwards would silently
    /// generate the wrong type.
    @Test("the innermost enclosing scope shadows an outer one")
    func innermostScopeShadows() {
        #expect(
            TypeShapeBuilder.resolvedSpelling("Kind", enclosing: "Outer.Inner", universe: Self.universe)
                == "Outer.Inner.Kind"
        )
        #expect(
            TypeShapeBuilder.resolvedSpelling("Kind", enclosing: "Outer", universe: Self.universe)
                == "Outer.Kind"
        )
        // No nested `Kind` under `Wrapper`, so file scope wins and it stays bare.
        #expect(
            TypeShapeBuilder.resolvedSpelling("Kind", enclosing: "Wrapper", universe: Self.universe)
                == "Kind"
        )
    }

    /// Whole-identifier matching. `Kind` must not rewrite inside
    /// `CardinalityFieldKind` or `KindResolver` — both real names in this repo,
    /// and a substring rewriter would corrupt them into
    /// `CardinalityFieldOuter.Kind`.
    ///
    /// **The decoy has to share a spelling with a resolvable name, and finding
    /// that out took mutation testing.** The first version of this test passed a
    /// decoy on its own, and a mutant that swapped whole-word substitution for
    /// `replacingOccurrences` *survived* — because the loop only invokes the
    /// replacer for identifiers whose qualified candidate is actually in the
    /// universe. `CardinalityFieldKind` alone has no candidate, so it never
    /// reaches the replacer and a substring bug is unreachable. The decoy is only
    /// a decoy when something else in the same spelling is being rewritten.
    @Test("substitution is whole-identifier, never substring")
    func substitutionIsWholeIdentifier() {
        // Decoy alone — untouched, but this does not exercise the replacer.
        for decoy in ["CardinalityFieldKind", "KindResolver"] {
            #expect(
                TypeShapeBuilder.resolvedSpelling(decoy, enclosing: "Outer", universe: Self.universe)
                    == decoy
            )
        }
        // Decoy *alongside* a resolvable name — this is the case that bites. A
        // substring rewriter turns `CardinalityFieldKind` into
        // `CardinalityFieldOuter.Kind` while correctly qualifying the bare `Kind`.
        let mixed = [
            ("[CardinalityFieldKind: Kind]", "[CardinalityFieldKind: Outer.Kind]"),
            ("[Kind: KindResolver]", "[Outer.Kind: KindResolver]"),
            ("Array<KindResolver>?", "Array<KindResolver>?"),
            ("[Kind]", "[Outer.Kind]")
        ]
        for (input, expected) in mixed {
            #expect(
                TypeShapeBuilder.resolvedSpelling(input, enclosing: "Outer", universe: Self.universe)
                    == expected,
                "\(input) resolved wrong"
            )
        }
    }

    /// A spelling mixing an **already-qualified** name with a bare one. The
    /// qualified half must survive untouched while the bare half is rewritten.
    ///
    /// This is the other case a naive rewriter fails: treat `.` as a separator
    /// rather than part of an identifier and `Outer.Kind` decomposes into
    /// `Outer` + `Kind`, the bare `Kind` matches, and the qualified half becomes
    /// `Outer.Outer.Kind`.
    @Test("a qualified and a bare name in one spelling resolve independently")
    func qualifiedAndBareNamesCoexist() {
        let cases = [
            ("[Outer.Kind: Kind]", "[Outer.Kind: Outer.Kind]"),
            ("[Outer.Inner.Kind]", "[Outer.Inner.Kind]"),
            ("[String: Outer.StoredMember]", "[String: Outer.StoredMember]")
        ]
        for (input, expected) in cases {
            #expect(
                TypeShapeBuilder.resolvedSpelling(input, enclosing: "Outer", universe: Self.universe)
                    == expected,
                "\(input) resolved wrong"
            )
        }
    }

    /// The composite shapes `SemanticIndexEntry` and `IndexedTypeShape` actually
    /// use — this is the case that was emitting bare `Kind` / `StoredMember` and
    /// failing to compile in the verifier.
    @Test("composite spellings resolve through their decoration")
    func compositeSpellingsResolve() {
        let cases = [
            ("Kind", "Outer.Kind"),
            ("Kind?", "Outer.Kind?"),
            ("[StoredMember]", "[Outer.StoredMember]"),
            ("[StoredMember]?", "[Outer.StoredMember]?"),
            ("[String: Kind]", "[String: Outer.Kind]"),
            ("[[StoredMember]]", "[[Outer.StoredMember]]"),
            ("Array<Kind>", "Array<Outer.Kind>")
        ]
        for (input, expected) in cases {
            #expect(
                TypeShapeBuilder.resolvedSpelling(input, enclosing: "Outer", universe: Self.universe)
                    == expected,
                "\(input) resolved wrong"
            )
        }
    }

    /// An already-qualified spelling is left alone — the concrete case behind the
    /// idempotence law.
    @Test("already-qualified spellings pass through")
    func alreadyQualifiedPassesThrough() {
        for spelling in ["Outer.Kind", "[Outer.StoredMember]", "Outer.Inner.Kind"] {
            #expect(
                TypeShapeBuilder.resolvedSpelling(
                    spelling, enclosing: "Outer", universe: Self.universe
                ) == spelling
            )
        }
    }

    /// **A nested type may legitimately shadow a stdlib name, and resolution must
    /// honour it.** `Outer.Inner` exists, so a member of `Outer` typed `Inner`
    /// qualifies; but `String` is not nested under `Outer`, so it stays bare even
    /// though the universe contains a top-level `String` entry.
    @Test("stdlib names qualify only when genuinely shadowed")
    func stdlibNamesQualifyOnlyWhenShadowed() {
        #expect(
            TypeShapeBuilder.resolvedSpelling("Inner", enclosing: "Outer", universe: Self.universe)
                == "Outer.Inner"
        )
        #expect(
            TypeShapeBuilder.resolvedSpelling("String", enclosing: "Outer", universe: Self.universe)
                == "String"
        )
        // …but if someone *does* nest a `String`, the member means that one.
        var shadowed = Self.universe
        shadowed.insert("Outer.String")
        #expect(
            TypeShapeBuilder.resolvedSpelling("String", enclosing: "Outer", universe: shadowed)
                == "Outer.String"
        )
    }

    /// An empty universe is a no-op, and an empty enclosing scope resolves
    /// nothing — the degenerate inputs a top-level type actually hits.
    @Test("degenerate inputs are no-ops")
    func degenerateInputsAreNoOps() {
        #expect(TypeShapeBuilder.resolvedSpelling("Kind", enclosing: "Outer", universe: []) == "Kind")
        #expect(TypeShapeBuilder.resolvedSpelling("Kind", enclosing: "", universe: Self.universe) == "Kind")
        #expect(TypeShapeBuilder.resolvedSpelling("", enclosing: "Outer", universe: Self.universe).isEmpty)
    }
}
