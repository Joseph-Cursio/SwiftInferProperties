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
//
// **AND IT DID NOT, 2026-08-28 — the law was right and its GENERATOR could not
// reach the field.** `assertsPrecondition` and `delegatesToSelf` were both dropped by
// the mirror; `mirrorRoundTripsKitShape` asserts
// `restored.initializers == shape.initializers` and `shapeGen` drew
// `initializers: []` on every draw, so that line compared `[] == []` forever. The
// omission it was written to catch was a field on the *outer* shape; a field on a
// nested one was outside the domain.
//
// That is this repo's own standing finding arriving inside its own guard — *reach is
// necessary and not sufficient* (`fixtures/branch-reaching-generator/README.md`), and
// *a control with no population is not a control*
// (`docs/measurements/cross-type-roundtrip-census.md`). The fix is the generator, not
// another assertion: `structShapeGen` below draws initializers carrying both flags, and
// `mirrorPreservesTheDerivedStrategyForStructs` states the consequence in the currency
// that matters — the kit picks a different derivation tier when a flag is lost.
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

    /// Initializers carrying **both** precondition flags, plus the failable/throwing
    /// pair. Every field varies: a generator that pinned any of them to its default
    /// would let a dropped field pass exactly the way `shapeGen`'s `initializers: []`
    /// did.
    ///
    /// `accessLevel` is deliberately left at `.implicit` — see
    /// `initializerAccessLevelIsKnowinglyNotCarried`, which states that drop out loud
    /// rather than letting this generator hide it.
    private static let initializerGen = zip(
        Gen.element(of: [true, false]).map { $0! },
        Gen.element(of: [true, false]).map { $0! },
        Gen.element(of: [true, false]).map { $0! },
        Gen<Int>.int(in: 1...3)
    ).map { asserts, delegates, isFailable, arity in
        PropertyLawCore.InitializerSignature(
            parameters: (0..<arity).map { index in
                PropertyLawCore.InitializerParameter(
                    label: index == 0 ? nil : "arg\(index)",
                    typeName: Self.typeSpellings[index % Self.typeSpellings.count]
                )
            },
            isFailable: isFailable,
            isThrowing: false,
            assertsPrecondition: asserts,
            delegatesToSelf: delegates
        )
    }

    /// A **struct** with user initializers — the shape `initializerBasedStrategy` reads.
    /// `shapeGen` produces enums with no initializers, which is why it could not witness
    /// a lost initializer field in either currency: not by equality, and not by
    /// derivation tier, since Tier 6 declines a non-struct outright.
    private static let structShapeGen = zip(
        Gen.element(of: names).map { $0! },
        initializerGen.array(of: 1...3)
    ).map { name, initializers in
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [],
            hasUserInit: true,
            initializers: initializers,
            enumCases: []
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

    /// **The law `shapeGen` could not state.** Same assertion as
    /// `mirrorRoundTripsKitShape`, over shapes that actually carry initializers.
    /// Fails on either precondition flag being dropped by the mirror.
    @Test("the mirror round-trips a struct's initializers unchanged")
    func mirrorRoundTripsInitializers() async {
        await propertyCheck(input: Self.structShapeGen) { shape in
            let restored = IndexedTypeShape(from: shape).toKitShape()
            #expect(restored.initializers == shape.initializers)
            #expect(
                restored.initializers.map(\.assertsPrecondition)
                    == shape.initializers.map(\.assertsPrecondition)
            )
            #expect(
                restored.initializers.map(\.delegatesToSelf)
                    == shape.initializers.map(\.delegatesToSelf)
            )
        }
    }

    /// The consequence, in the currency that matters. `InitializerBasedDerivation`
    /// declines an initializer that asserts, and declines a delegating one when any
    /// sibling asserts — so losing either flag through the mirror turns a `.todo` into a
    /// live `.initializerBased` derivation that traps at run time instead of failing.
    @Test("the mirror does not change the strategy for a struct with preconditions")
    func mirrorPreservesTheDerivedStrategyForStructs() async {
        await propertyCheck(input: Self.structShapeGen) { shape in
            let direct = DerivationStrategist.strategy(for: shape)
            let viaMirror = DerivationStrategist.strategy(
                for: IndexedTypeShape(from: shape).toKitShape()
            )
            #expect(direct == viaMirror, "the mirror changed the derivation for \(shape.name)")
        }
    }

    /// **`accessLevel` IS dropped, and that is deliberate — asserted so it is a stated
    /// choice rather than the next silent one.**
    ///
    /// `MemberBlockInspector.initializers(in:)` excludes `private` and `fileprivate`
    /// initializers at capture, which is strictly stronger than what the kit's
    /// `isCallable(from: .separateFile)` would decline: every level that survives
    /// capture — `internal` and wider — is callable from both emission sites, so the
    /// `.implicit` default this restores is behaviourally identical for anything the
    /// scanner can produce.
    ///
    /// It stops being identical the day capture stops filtering, which is what this test
    /// is here to make visible.
    @Test("initializer accessLevel is knowingly not carried")
    func initializerAccessLevelIsKnowinglyNotCarried() {
        let shape = TypeShape(
            name: "Subject",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            hasUserInit: true,
            initializers: [
                PropertyLawCore.InitializerSignature(
                    parameters: [PropertyLawCore.InitializerParameter(label: nil, typeName: "Int")],
                    accessLevel: .public
                )
            ]
        )
        let restored = IndexedTypeShape(from: shape).toKitShape()
        #expect(restored.initializers.first?.accessLevel == .implicit)
        #expect(restored.initializers.first?.accessLevel.isCallable(from: .separateFile) == true)
        #expect(restored.initializers.first?.accessLevel.isCallable(from: .sameFile) == true)
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

    /// Same additive treatment for the two precondition flags: an index written before
    /// they existed reads them as `false`, which is the behaviour that shipped. Swift's
    /// synthesized decoder does not fall back to a property's default value for a
    /// missing key, so `InitializerSignature` carries a hand-written `init(from:)` and
    /// this is what checks it.
    @Test("an index without the precondition flags still decodes")
    func legacyIndexWithoutPreconditionFlagsDecodes() throws {
        let initializer = #"{"parameters":[{"typeName":"Int"}],"isFailable":false,"isThrowing":false}"#
        let legacy = #"{"name":"Subject","kind":"struct","inheritedTypes":[],"# +
            #""hasUserGen":false,"hasUserInit":true,"initializers":[\#(initializer)]}"#

        let decoded = try JSONDecoder().decode(IndexedTypeShape.self, from: Data(legacy.utf8))
        let signature = try #require(decoded.initializers.first)
        #expect(signature.assertsPrecondition == false)
        #expect(signature.delegatesToSelf == false)
        #expect(signature.parameters.count == 1)
    }

    /// **The `Euclid.Plane` regression, as a shape.** A struct whose chosen initializer
    /// asserts nothing and delegates to a sibling that does. The kit declines exactly
    /// this — *delegates AND some initializer on this type asserts* — and could not,
    /// because neither flag reached it through the index.
    ///
    /// Before the fix this derived a live generator, and the first generated kit suite
    /// that ever compiled died on `assert(normal.isNormalized)` at `Plane.swift:230`
    /// (`docs/measurements/kit-scaffold-conversion.md` §3.2). The failure is a **trap**,
    /// not a refuted law: the process aborts and every remaining law in the suite goes
    /// unrun.
    @Test("a delegating initializer inherits its sibling's precondition through the mirror")
    func delegatingInitializerIsDeclinedThroughTheMirror() {
        let planeShaped = TypeShape(
            name: "Plane",
            kind: .struct,
            inheritedTypes: ["Hashable"],
            hasUserGen: false,
            hasUserInit: true,
            initializers: [
                // `init(unchecked normal:pointOnPlane:)` — forwards, asserts nothing itself.
                PropertyLawCore.InitializerSignature(
                    parameters: [
                        PropertyLawCore.InitializerParameter(label: "unchecked", typeName: "Vector"),
                        PropertyLawCore.InitializerParameter(label: "pointOnPlane", typeName: "Vector")
                    ],
                    assertsPrecondition: false,
                    delegatesToSelf: true
                ),
                // `init(unchecked normal:w:)` — holds `assert(normal.isNormalized)`.
                PropertyLawCore.InitializerSignature(
                    parameters: [
                        PropertyLawCore.InitializerParameter(label: "unchecked", typeName: "Vector"),
                        PropertyLawCore.InitializerParameter(label: "w", typeName: "Double")
                    ],
                    assertsPrecondition: true,
                    delegatesToSelf: false
                )
            ]
        )

        let viaMirror = IndexedTypeShape(from: planeShaped).toKitShape()
        #expect(viaMirror.initializers.map(\.delegatesToSelf) == [true, false])
        #expect(viaMirror.initializers.map(\.assertsPrecondition) == [false, true])

        let strategy = DerivationStrategist.strategy(for: viaMirror)
        if case .initializerBased = strategy {
            let message = "the mirror admitted a delegating initializer whose sibling asserts"
                + " — this is the shape that traps the whole suite at run time"
            Issue.record(Comment(rawValue: message))
        }
        #expect(strategy == DerivationStrategist.strategy(for: planeShaped))
    }
}
