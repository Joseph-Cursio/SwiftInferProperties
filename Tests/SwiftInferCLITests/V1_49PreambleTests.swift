import Foundation
import PropertyLawCore
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

// V1.49.E — unit tests for the V1.49.A stub-preamble channel.

@Suite("V1.49.A — stub-preamble channel across all 5 emitters")
struct V1_49PreambleTests {

    private static let canonicalSeed = RoundTripStubEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static let canonicalPreamble = """
    extension Int {
        mutating func bumpInPlace() { self += 1 }
    }
    """

    // MARK: - RoundTripStubEmitter

    @Test("RoundTrip: preamble defaults to empty + emit stays byte-stable")
    func roundTripDefaultEmpty() throws {
        let inputs = RoundTripStubEmitter.Inputs(
            forwardCall: "{ (x: Int) in x }",
            inverseCall: "{ (x: Int) in x }",
            extraImports: [],
            carrierType: "Int",
            seedHex: Self.canonicalSeed,
            trialBudget: .small
        )
        let source = try RoundTripStubEmitter.emit(inputs)
        #expect(!source.contains("bumpInPlace"))
    }

    @Test("RoundTrip: non-empty preamble renders verbatim in setup section")
    func roundTripWithPreamble() throws {
        let inputs = RoundTripStubEmitter.Inputs(
            forwardCall: "{ (x: Int) in x }",
            inverseCall: "{ (x: Int) in x }",
            extraImports: [],
            carrierType: "Int",
            seedHex: Self.canonicalSeed,
            trialBudget: .small,
            preamble: Self.canonicalPreamble
        )
        let source = try RoundTripStubEmitter.emit(inputs)
        #expect(source.contains("extension Int {"))
        #expect(source.contains("mutating func bumpInPlace()"))
        // Preamble is positioned after imports + before var rng.
        let importsEnd = source.range(of: "import")!.lowerBound
        let preambleStart = source.range(of: "extension Int")!.lowerBound
        let rngStart = source.range(of: "var rng")!.lowerBound
        #expect(importsEnd < preambleStart)
        #expect(preambleStart < rngStart)
    }

    // MARK: - StrategistDispatchEmitter

    @Test("StrategistDispatch: preamble renders in setup section")
    func strategistWithPreamble() throws {
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "idempotence",
                functionCalls: ["{ (x: Int) in x }"],
                extraImports: [],
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: Self.canonicalPreamble
            )
        )
        #expect(source.contains("mutating func bumpInPlace()"))
        // Preamble is positioned before var rng.
        let preambleStart = source.range(of: "extension Int")!.lowerBound
        let rngStart = source.range(of: "var rng")!.lowerBound
        #expect(preambleStart < rngStart)
    }

    // MARK: - All 5 emitters round-trip the preamble field

    @Test("Idempotence + Commutativity + Associativity emitters thread the preamble")
    func nonRoundTripEmittersThreadPreamble() throws {
        let preamble = "extension Int {\n    var sentinel: Int { 42 }\n}"
        let idem = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: "{ (x: Int) in x }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        let comm = try CommutativityStubEmitter.emit(
            CommutativityStubEmitter.Inputs(
                functionCall: "{ (a: Int, b: Int) in a + b }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        let assoc = try AssociativityStubEmitter.emit(
            AssociativityStubEmitter.Inputs(
                functionCall: "{ (a: Int, b: Int) in a + b }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        #expect(idem.contains("sentinel: Int"))
        #expect(comm.contains("sentinel: Int"))
        #expect(assoc.contains("sentinel: Int"))
    }

    @Test("multi-line preamble preserves line breaks verbatim")
    func multilinePreambleRoundTrips() throws {
        let preamble = """
        // Comment line 1
        // Comment line 2
        let foo: Int = 0
        """
        let source = try IdempotenceStubEmitter.emit(
            IdempotenceStubEmitter.Inputs(
                functionCall: "{ (x: Int) in x }",
                extraImports: [],
                carrierType: "Int",
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                preamble: preamble
            )
        )
        #expect(source.contains("// Comment line 1"))
        #expect(source.contains("// Comment line 2"))
        #expect(source.contains("let foo: Int = 0"))
    }
}

// V1.49.E — unit tests for the V1.49.B .memberwiseArbitrary emit.

@Suite("V1.49.B — memberwiseArbitrary strategy emit")
struct V1_49MemberwiseTests {

    @Test("1-member struct emits map() with constructor call")
    func singleMemberEmitShape() throws {
        let shape = IndexedTypeShape(
            name: "Wrapper",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "value", typeName: "Int")
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Wrapper", typeShape: shape
        )
        #expect(recipe.expression.contains("Gen<Int>.int()"))
        #expect(recipe.expression.contains(".map"))
        #expect(recipe.expression.contains("Wrapper(value: $0)"))
        #expect(!recipe.expression.contains("zip("))
    }

    @Test("2-member struct emits zip(g1, g2).map composition")
    func twoMemberEmitShape() throws {
        let shape = IndexedTypeShape(
            name: "Pair",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "x", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "y", typeName: "String")
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Pair", typeShape: shape
        )
        #expect(recipe.expression.contains("zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8))"))
        #expect(recipe.expression.contains("(m0, m1)"))
        #expect(recipe.expression.contains("Pair(x: m0, y: m1)"))
    }

    @Test("3-member struct emits zip(g1, g2, g3).map composition")
    func threeMemberEmitShape() throws {
        let shape = IndexedTypeShape(
            name: "Triple",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "a", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "b", typeName: "Int"),
                IndexedTypeShape.StoredMember(name: "c", typeName: "Bool")
            ],
            hasUserInit: false
        )
        let recipe = try StrategistDispatchEmitter.resolveRecipe(
            carrier: "Triple", typeShape: shape
        )
        #expect(recipe.expression.contains("zip(Gen<Int>.int(), Gen<Int>.int(), Gen<Bool>.bool())"))
        #expect(recipe.expression.contains("(m0, m1, m2)"))
        #expect(recipe.expression.contains("Triple(a: m0, b: m1, c: m2)"))
    }

    @Test("non-stdlib member type falls through to .todo via strategist")
    func nonStdlibMemberFallsThroughToTodo() throws {
        // Stored property URL is not in RawType — strategist returns
        // .todo, our emitter throws .unsupportedCarrier.
        let shape = IndexedTypeShape(
            name: "Unsupported",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [
                IndexedTypeShape.StoredMember(name: "u", typeName: "URL")
            ],
            hasUserInit: false
        )
        #expect(throws: VerifyError.self) {
            _ = try StrategistDispatchEmitter.resolveRecipe(
                carrier: "Unsupported", typeShape: shape
            )
        }
    }
}

// V1.49.E — unit tests for V1.49.C secondaryFunctionName + resolver fallback.

@Suite("V1.49.C — secondaryFunctionName + non-curated pair resolver fallback")
struct V1_49SecondaryFunctionNameTests {

    private static func entry(
        primary: String,
        secondary: String? = nil,
        carrier: String = "Complex<Double>"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xABCD1234EFFE5678",
            templateName: "round-trip",
            typeName: carrier,
            score: 30,
            tier: "Possible",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-12T00:00:00Z",
            lastSeenAt: "2026-05-12T00:00:00Z",
            secondaryFunctionName: secondary
        )
    }

    @Test("curated pair lookup still wins when present")
    func curatedTakesPrecedence() throws {
        // exp(_:) is in the curated list. The resolver uses the
        // curated inverse `log(_:)`, ignoring any secondaryFunctionName.
        // V1.52.A — exp/log on Complex carrier now render as the
        // free-function form (swift-numerics ships global
        // `exp<T: ElementaryFunctions>(_:)` overloads); the static
        // `Complex.exp` form compiled but cycle-48 surfaced runtime
        // SIGABRTs from the static-vs-free-function divergence.
        let result = try RoundTripPairResolver.resolve(
            Self.entry(primary: "exp(_:)", secondary: "WRONG(_:)")
        )
        #expect(result.forwardCall == "exp")
        #expect(result.inverseCall == "log")
    }

    @Test("non-curated pair falls back to secondaryFunctionName")
    func nonCuratedFallbackUsesSecondary() throws {
        // _minimumCapacity/_scale isn't in the curated list. The
        // resolver should reach for the secondaryFunctionName.
        let result = try RoundTripPairResolver.resolve(
            Self.entry(
                primary: "_minimumCapacity(forScale:)",
                secondary: "_scale(forMinimumCapacity:)",
                carrier: "Int"
            )
        )
        #expect(result.forwardCall == "Int._minimumCapacity")
        #expect(result.inverseCall == "Int._scale")
    }

    @Test("no curated match + no secondary → .unsupportedPair")
    func unsupportedPairWhenBothMiss() throws {
        #expect(throws: VerifyError.self) {
            _ = try RoundTripPairResolver.resolve(
                Self.entry(primary: "unknown(_:)", secondary: nil, carrier: "Int")
            )
        }
    }

    @Test("JSON round-trip preserves secondaryFunctionName")
    func jsonRoundTripsSecondary() throws {
        let original = Self.entry(
            primary: "_minimumCapacity(forScale:)",
            secondary: "_scale(forMinimumCapacity:)"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.secondaryFunctionName == "_scale(forMinimumCapacity:)")
        #expect(decoded == original)
    }

    @Test("pre-v1.49 JSON (no secondaryFunctionName) decodes cleanly as nil")
    func preV49JsonMigrates() throws {
        // Verbatim pre-v1.49 entry JSON — no secondaryFunctionName key.
        let json = """
        {
            "firstSeenAt": "2026-05-10T00:00:00Z",
            "identityHash": "0xBC43359C0574816B",
            "lastSeenAt": "2026-05-11T12:34:56Z",
            "location": "/foo/Bar.swift:1",
            "primaryFunctionName": "exp(_:)",
            "score": 30,
            "templateName": "round-trip",
            "tier": "Possible",
            "typeName": "Complex<Double>"
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(SemanticIndexEntry.self, from: data)
        #expect(decoded.secondaryFunctionName == nil)
        #expect(decoded.primaryFunctionName == "exp(_:)")
    }

    @Test("updated(from:) propagates secondaryFunctionName from other")
    func updatedPropagatesSecondary() {
        let original = Self.entry(primary: "exp(_:)", secondary: nil)
        let newer = Self.entry(primary: "exp(_:)", secondary: "log(_:)")
        let merged = original.updated(from: newer)
        #expect(merged.secondaryFunctionName == "log(_:)")
    }
}
