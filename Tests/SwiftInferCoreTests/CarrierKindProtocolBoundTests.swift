import PropertyLawCore
@testable import SwiftInferCore
import Testing

/// Protocol decls became visible to `CarrierKindResolver` on 2026-07-30, when the scanner
/// started recording them for their inheritance clause. This suite covers what that exposure
/// does and does not change.
///
/// The hazard: a protocol record carries **no stored members**, so without a guard it falls
/// straight through to `classifyMembers([])`, whose documented default is *"empty stored
/// properties → value-semantic by default."* For an `AnyObject`-constrained existential that
/// is not a heuristic, it is false — and `.valueSemantic` is a **+5 scoring signal** carrying
/// the claim *"algebraic property is well-defined under aliasing,"* which is exactly the claim
/// a reference type breaks.
@Suite("CarrierKindResolver — protocol carriers and the class-bound guard")
struct CarrierKindProtocolBoundTests {

    private func proto(_ name: String, _ inherited: [String]) -> TypeDecl {
        TypeDecl(
            name: name,
            kind: .protocol,
            inheritedTypes: inherited,
            location: SourceLocation(file: "P.swift", line: 1, column: 1)
        )
    }

    @Test("an AnyObject-bound protocol carrier is a reference type")
    func anyObjectBoundProtocolIsReference() {
        let resolver = CarrierKindResolver(typeDecls: [proto("Delegate", ["AnyObject"])])
        #expect(resolver.classify(typeName: "Delegate") == .referenceType)
    }

    @Test("the legacy `: class` spelling counts too")
    func legacyClassBoundSpelling() {
        // The scanner records the inheritance clause verbatim, so both spellings reach here.
        let resolver = CarrierKindResolver(typeDecls: [proto("Legacy", ["class"])])
        #expect(resolver.classify(typeName: "Legacy") == .referenceType)
    }

    @Test("the bound wins even when listed after other refinements")
    func boundIsFoundAnywhereInTheClause() {
        let resolver = CarrierKindResolver(
            typeDecls: [proto("Observed", ["Equatable", "AnyObject", "CustomStringConvertible"])]
        )
        #expect(resolver.classify(typeName: "Observed") == .referenceType)
    }

    /// The deliberate limit, pinned so it reads as a decision rather than an oversight.
    ///
    /// An unconstrained protocol can still be adopted by a class, so `.valueSemantic` is not
    /// *sound* here either. It is nonetheless the resolver's long-standing answer for every
    /// protocol carrier reached through an **extension** record — which is why `FloatingPoint`
    /// and `BinaryInteger` already classified as value-semantic on `stdlib/public/core`, and
    /// why recording protocol decls left that corpus's carrier classification unmoved.
    /// Tightening it is a separate, measurable decision, not a rider on a scanner fix.
    @Test("an UNCONSTRAINED protocol keeps the pre-existing value-semantic answer")
    func unconstrainedProtocolIsUnchanged() {
        let resolver = CarrierKindResolver(typeDecls: [proto("Shape", ["Equatable"])])
        #expect(
            resolver.classify(typeName: "Shape") == .valueSemantic,
            """
            If this flips, it must be because someone tightened the protocol posture on \
            purpose and measured the corpora — not as a side effect.
            """
        )
    }

    /// A class-bound protocol whose name is *also* extended must not have the bound diluted:
    /// the extension record contributes an empty member list, and empty-means-value-semantic
    /// would otherwise win by arriving at `classifyMembers` first.
    @Test("an extension record alongside the protocol does not dilute the bound")
    func extensionRecordDoesNotOverrideTheBound() {
        let decls = [
            proto("Delegate", ["AnyObject"]),
            TypeDecl(
                name: "Delegate",
                kind: .extension,
                inheritedTypes: [],
                location: SourceLocation(file: "P.swift", line: 9, column: 1)
            )
        ]
        #expect(CarrierKindResolver(typeDecls: decls).classify(typeName: "Delegate") == .referenceType)
    }

    /// End to end from source, so this fails if the scanner stops recording the clause even
    /// when the resolver guard is intact.
    @Test("scanner → resolver, end to end on a class-bound protocol")
    func endToEndFromSource() {
        let corpus = FunctionScanner.scanCorpus(
            source: "protocol Delegate: AnyObject { func fire() }", file: "P.swift"
        )
        let resolver = CarrierKindResolver(typeDecls: corpus.typeDecls)
        #expect(resolver.classify(typeName: "Delegate") == .referenceType)
    }

    /// A concrete `class` still wins outright — the pre-existing `.class`/`.actor` check runs
    /// before the protocol guard and is unaffected by it.
    @Test("a concrete class carrier is unaffected")
    func concreteClassIsUnaffected() {
        let decls = [
            TypeDecl(
                name: "Box",
                kind: .class,
                inheritedTypes: [],
                location: SourceLocation(file: "B.swift", line: 1, column: 1)
            )
        ]
        #expect(CarrierKindResolver(typeDecls: decls).classify(typeName: "Box") == .referenceType)
    }
}
