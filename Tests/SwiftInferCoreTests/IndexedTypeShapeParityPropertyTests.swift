import Foundation
import PropertyLawCore
import PropertyLawKit
@testable import SwiftInferCore
import Testing

// Self-dogfood road test (`docs/measurements/roadtest-self-dogfood.md` §11.3) — the guard for
// the failure mode that bit three times.
//
// `IndexedTypeShape` is the persisted mirror of the kit's `TypeShape`, and its
// header claims "field-for-field parity". `enumCases` broke that claim silently:
// the field simply did not exist, so an enum's cases were dropped on the way
// into `.swiftinfer/index.json`. At verify time the strategist then saw an enum
// with no cases, `enumCasesStrategy` returned `nil`, and derivation fell through
// to `.rawRepresentable` — a filter over random raw values that for a
// `String`-raw enum never produces one and never terminates.
//
// The cost was two verifier binaries at 99.9% CPU for the better part of an
// hour with the survey reporting nothing at all. And the shape of the bug is
// what makes it worth a dedicated suite: **the kit reasons over a projection
// this repo controls, so every field the projection omits silently disables
// whichever kit tier depends on it, with no error at either end.** The kit's
// tests pass. The index looks complete. Only an end-to-end run shows the tier is
// dead.
//
// So these are round-trip laws, not spot checks. A field added to `TypeShape`
// and forgotten here fails `everyKitFieldSurvivesTheRoundTrip`.
@Suite("Road test — IndexedTypeShape ⇄ TypeShape parity")
struct IndexedTypeShapeParityPropertyTests {

    // MARK: - Generators

    private static let names = ["Kind", "Status", "Outer.Kind", "SeedRole"]
    private static let typeSpellings = ["String", "Int", "[String]", "Outer.Kind?"]

    private static let caseGen = zip(
        Gen.element(of: ["ok", "notFound", "`struct`", "`class`"]).map { $0! },
        Gen<Int>.int(in: 0...2)
    ).map { name, valueCount in
        PropertyLawCore.EnumCase(
            name: name,
            associatedValues: (0..<valueCount).map { index in
                PropertyLawCore.InitializerParameter(
                    label: index == 0 ? nil : "arg\(index)",
                    typeName: Self.typeSpellings[index % Self.typeSpellings.count]
                )
            }
        )
    }

    private static let shapeGen = zip(
        Gen.element(of: names).map { $0! },
        caseGen.array(of: 0...4),
        Gen.element(of: [true, false]).map { $0! }
    ).map { name, cases, hasUserGen in
        TypeShape(
            name: name,
            kind: .enum,
            inheritedTypes: ["String", "Codable"],
            hasUserGen: hasUserGen,
            storedMembers: [],
            hasUserInit: false,
            initializers: [],
            enumCases: cases
        )
    }

    // MARK: - Round-trip laws

    /// **The parity law.** `TypeShape → IndexedTypeShape → TypeShape` is the
    /// identity. A field added to the kit's shape and forgotten in the mirror
    /// fails here, which is the whole point — the previous omission produced no
    /// error anywhere, just a quietly disabled derivation tier.
    @Test("the mirror round-trips a kit shape unchanged")
    func mirrorRoundTripsKitShape() async {
        await propertyCheck(input: Self.shapeGen) { shape in
            let restored = IndexedTypeShape(from: shape).toKitShape()
            #expect(restored.name == shape.name)
            #expect(restored.kind == shape.kind)
            #expect(restored.inheritedTypes == shape.inheritedTypes)
            #expect(restored.hasUserGen == shape.hasUserGen)
            #expect(restored.hasUserInit == shape.hasUserInit)
            #expect(restored.enumCases == shape.enumCases)
            #expect(restored.storedMembers == shape.storedMembers)
            #expect(restored.initializers == shape.initializers)
        }
    }

    /// The JSON hop is lossless too — the mirror is persisted, so a field that
    /// survives conversion but not encoding is just as dead.
    @Test("the mirror round-trips through JSON unchanged")
    func mirrorRoundTripsThroughJSON() async {
        await propertyCheck(input: Self.shapeGen) { shape in
            let mirror = IndexedTypeShape(from: shape)
            let decoded = try? JSONDecoder().decode(
                IndexedTypeShape.self, from: JSONEncoder().encode(mirror)
            )
            #expect(decoded == mirror)
            #expect(decoded?.enumCases.map(\.name) == shape.enumCases.map(\.name))
        }
    }

    /// **The law that would have caught the original omission**, stated over the
    /// thing that actually matters: the *strategy* the kit picks must not change
    /// by passing through the mirror. A dropped field shows up here as a
    /// different derivation tier, which is exactly what happened — `.enumCases`
    /// silently became `.rawRepresentable`.
    @Test("the mirror does not change which strategy the kit derives")
    func mirrorPreservesTheDerivedStrategy() async {
        await propertyCheck(input: Self.shapeGen) { shape in
            let direct = DerivationStrategist.strategy(for: shape)
            let viaMirror = DerivationStrategist.strategy(for: IndexedTypeShape(from: shape).toKitShape())
            #expect(direct == viaMirror, "the mirror changed the derivation for \(shape.name)")
        }
    }

    // MARK: - The specific regression

    /// The exact shape that hung: a `String`-raw enum with cases, not
    /// `CaseIterable`. Through the mirror it must still derive `.enumCases` —
    /// before the fix it arrived case-less and derived the non-terminating
    /// `.rawRepresentable` filter.
    @Test("a String-raw enum keeps its cases through the mirror")
    func stringRawEnumKeepsItsCases() {
        let shape = TypeShape(
            name: "IndexedTypeShape.Kind",
            kind: .enum,
            inheritedTypes: ["String", "Codable", "Sendable", "Equatable"],
            hasUserGen: false,
            enumCases: [
                PropertyLawCore.EnumCase(name: "`struct`"),
                PropertyLawCore.EnumCase(name: "`class`"),
                PropertyLawCore.EnumCase(name: "`enum`"),
                PropertyLawCore.EnumCase(name: "`actor`")
            ]
        )
        let viaMirror = IndexedTypeShape(from: shape).toKitShape()
        #expect(viaMirror.enumCases.count == 4)

        let strategy = DerivationStrategist.strategy(for: viaMirror)
        guard case .enumCases = strategy else {
            let message = "expected .enumCases through the mirror, got \(strategy)"
                + " — the raw fallback here is the generator that does not terminate"
            Issue.record(Comment(rawValue: message))
            return
        }
    }

    /// Keyword-escaped case names (`` `struct` ``) survive verbatim. They are
    /// interpolated straight into `Type.case` in the emitted generator, where
    /// the backticks are load-bearing — stripping them yields `Kind.struct`,
    /// which does not parse.
    @Test("keyword-escaped case names survive verbatim")
    func keywordEscapedCaseNamesSurvive() throws {
        let shape = TypeShape(
            name: "Kind",
            kind: .enum,
            inheritedTypes: ["String"],
            hasUserGen: false,
            enumCases: [PropertyLawCore.EnumCase(name: "`struct`")]
        )
        let decoded = try JSONDecoder().decode(
            IndexedTypeShape.self,
            from: JSONEncoder().encode(IndexedTypeShape(from: shape))
        )
        #expect(decoded.enumCases.first?.name == "`struct`")
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Kind",
            strategy: DerivationStrategist.strategy(for: decoded.toKitShape())
        )
        #expect(expression.contains("Kind.`struct`"))
    }

    /// Backward compatibility: an index written before the field existed decodes
    /// to `[]` rather than failing. The change is additive — no schema bump.
    @Test("an index without the field still decodes")
    func legacyIndexWithoutTheFieldDecodes() throws {
        let legacy = """
        {"name":"Kind","kind":"enum","inheritedTypes":["String"],"hasUserGen":false}
        """
        let decoded = try JSONDecoder().decode(IndexedTypeShape.self, from: Data(legacy.utf8))
        #expect(decoded.enumCases.isEmpty)
        #expect(decoded.name == "Kind")
    }
}
