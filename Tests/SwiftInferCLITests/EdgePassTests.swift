import Foundation
import PropertyLawCore
@testable import SwiftInferCLI
import Testing

/// Pass 2 for strategist-routed carriers.
///
/// It used to be `edgeSentinelSection()` — a hardcoded
/// `print("VERIFY_EDGE_RESULT: PASS")` with zero trials, asserting nothing,
/// which the renderer then reported as if an edge pass had run.
/// `fixtures/verify-refutability` measured the consequence: `mergedBound(_:)`,
/// wrong *only* at `Int.min`, came back holding. It now returns
/// `measured-edgeCaseAdvisory`.
@Suite("StrategistDispatchEmitter — advisory edge pass")
struct EdgePassTests {

    private static let seed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func inputs(
        carrier: String,
        template: String = "commutativity",
        calls: [String] = ["combine"]
    ) -> StrategistDispatchEmitter.Inputs {
        StrategistDispatchEmitter.Inputs(
            carrier: carrier,
            typeShape: nil,
            template: template,
            functionCalls: calls,
            seedHex: seed,
            trialBudget: .small
        )
    }

    // MARK: - The curated domains

    @Test("a signed carrier's boundary set spans min, max, zero and both units")
    func signedDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "Int"))
        #expect(values == ["Int.min", "Int.max", "0", "-1", "1"])
    }

    /// `-1` does not compile as an unsigned literal, and `min` is `0`.
    @Test("an unsigned carrier's boundary set omits the negatives")
    func unsignedDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "UInt"))
        #expect(!values.contains("-1"))
        #expect(!values.contains("UInt.min"))
        #expect(values.contains("UInt.max"))
    }

    @Test("fixed-width carriers get their own extremes")
    func fixedWidthDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "Int8"))
        #expect(values.contains("Int8.min"))
        #expect(values.contains("Int8.max"))
    }

    @Test("String's boundary set leads with the empty string")
    func stringDomain() throws {
        let values = try #require(StrategistDispatchEmitter.edgeDomainValues(for: "String"))
        #expect(values.first == #""""#)
    }

    /// A carrier with no meaningful finite boundary set keeps the sentinel, and
    /// the renderer then says no edge pass ran.
    @Test("a carrier with no curated boundary set has no edge domain")
    func noDomainForOtherCarriers() {
        #expect(StrategistDispatchEmitter.edgeDomainValues(for: "Bool") == nil)
        #expect(StrategistDispatchEmitter.edgeDomainValues(for: "Blob") == nil)
    }

    // MARK: - The emitted pass

    /// The law is composed once and reused, so it cannot drift between passes.
    /// What distinguishes Pass 2 is the generator and the marker prefix.
    @Test("an Int carrier emits a real Pass 2 over the boundary values")
    func intCarrierEmitsRealEdgePass() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(carrier: "Int"))
        #expect(source.contains("VERIFY_EDGE_RESULT"))
        #expect(source.contains("Int.min"))
        #expect(source.contains("Int.max"))
        // The zero-trial sentinel must be gone.
        #expect(!source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    /// Both passes declare bindings with the same names (`defaultGenerator`,
    /// `applyOnce`, …). Pass 2 is wrapped in `do { }` so those shadow rather
    /// than redeclare — which is what lets the composer be reused verbatim.
    @Test("Pass 2 is scoped so its bindings shadow rather than collide")
    func edgePassIsScoped() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(carrier: "Int"))
        #expect(source.contains("do {"))
        #expect(source.components(separatedBy: "let defaultGenerator").count - 1 == 2)
    }

    @Test("a carrier with no boundary set still gets the sentinel")
    func boolCarrierKeepsSentinel() throws {
        let source = try StrategistDispatchEmitter.emit(Self.inputs(carrier: "Bool"))
        #expect(source.contains("VERIFY_EDGE_TRIALS: 0"))
    }

    // MARK: - The relabel contract

    @Test("the relabel rewrites every default marker")
    func relabelRewritesMarkers() throws {
        let body = """
        print("VERIFY_DEFAULT_RESULT: FAIL")
        print("VERIFY_DEFAULT_TRIAL: 3")
        """
        let edge = try #require(StrategistDispatchEmitter.edgePassBody(fromDefaultBody: body))
        #expect(edge.contains("VERIFY_EDGE_RESULT"))
        #expect(edge.contains("VERIFY_EDGE_TRIAL"))
        #expect(!edge.contains("VERIFY_DEFAULT_"))
    }

    /// **Fails closed.** A composer shape carrying no default marker would
    /// relabel into a pass that prints nothing and asserts nothing — reporting
    /// success while checking zero properties, which is the exact defect this
    /// work exists to remove. Returning nil falls back to the sentinel, whose
    /// zero trial count the renderer reports honestly.
    @Test("a body with no default marker relabels to nil rather than a silent pass")
    func relabelFailsClosed() {
        #expect(StrategistDispatchEmitter.edgePassBody(fromDefaultBody: "print(\"hello\")") == nil)
        #expect(StrategistDispatchEmitter.edgePassBody(fromDefaultBody: "") == nil)
    }

    @Test("the edge recipe draws only from the boundary set")
    func edgeRecipeDrawsOnlyBoundaries() throws {
        let base = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Int>.int()", carrierTypeName: "Int", imports: ["PropertyBased"]
        )
        let edge = try #require(StrategistDispatchEmitter.edgeRecipe(from: base))
        #expect(edge.expression.contains("Gen<Int?>.element(of:"))
        #expect(edge.expression.contains("Int.min"))
        // No random draw mixed in — Pass 2 is boundary-only by construction.
        #expect(!edge.expression.contains("Gen.frequency"))
        #expect(edge.carrierTypeName == "Int")
    }

    @Test("a carrier with no boundary set yields no edge recipe")
    func noEdgeRecipeForOtherCarriers() {
        let base = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Blob.gen()", carrierTypeName: "Blob", imports: []
        )
        #expect(StrategistDispatchEmitter.edgeRecipe(from: base) == nil)
    }

    // MARK: - Composed carriers

    /// A struct is not a `RawType`, so `edgeDomainValues` answers `nil` for it
    /// and the whole carrier used to fall to the sentinel — **35 of the 130
    /// `measured-bothPass` verdicts** in the frozen whole-corpus survey
    /// (`fixtures/whole-corpus-survey/2026-08-05-whole-corpus.jsonl`), 27% of the
    /// passing verdicts reported with a boundary domain nothing had checked. The
    /// carrier's boundary set is the product of its leaves', and those are
    /// curated.
    @Test("a memberwise carrier's leaves carry the boundary sets the struct lacks")
    func memberwiseLeavesAreSwappedToBoundaries() throws {
        let members = [
            MemberSpec(name: "identity", rawType: .string),
            MemberSpec(name: "count", rawType: .int)
        ]
        let base = try StrategistDispatchEmitter.memberwiseRecipe(
            members: members, carrier: "Decisions"
        )
        // Precondition: the carrier itself has no boundary set — this is the
        // population that used to get the sentinel.
        #expect(StrategistDispatchEmitter.edgeDomainValues(for: "Decisions") == nil)

        let edge = try #require(StrategistDispatchEmitter.edgeRecipe(from: base))
        #expect(edge.carrierTypeName == "Decisions")
        #expect(edge.expression.contains("Int.min"))
        #expect(edge.expression.contains("Gen<String?>.element(of:"))
        // The construction half is byte-identical to Pass 1's — only the leaves
        // moved, so the two passes cannot state different laws.
        #expect(edge.expression.contains("Decisions(identity: m0, count: m1)"))
        // And the default draws are gone — Pass 2 is boundary-only.
        #expect(!edge.expression.contains(RawType.int.generatorExpression))
        #expect(!edge.expression.contains(RawType.string.generatorExpression))
    }

    /// **The measured reason this works on expressions rather than on
    /// `[MemberSpec]`.** Threading member specs was built first and moved
    /// **zero** of the 37 sentinel entries in an A/B, because every struct in
    /// that population declares a user `init` and so takes Tier 6
    /// `.initializerBased` — whose `InitArgument` has no `rawType` to key on.
    /// The rendered expression is the one thing every strategy has in common.
    @Test("an initializer-based carrier is reached, which member specs could not be")
    func initializerBasedCarrierIsReached() throws {
        // The shape `GeneratorExpressionEmitter` renders for Tier 6 — no
        // `MemberSpec` anywhere in it.
        let base = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "zip(\(RawType.string.generatorExpression), "
                + "\(RawType.int.generatorExpression)).map { (m0, m1) in "
                + "ReducerPin(moduleName: m0, functionName: m1) }",
            carrierTypeName: "ReducerPin",
            imports: ["Foundation", "PropertyBased"]
        )
        let edge = try #require(StrategistDispatchEmitter.edgeRecipe(from: base))
        #expect(edge.expression.contains("Int.min"))
        #expect(edge.expression.contains("Gen<String?>.element(of:"))
        #expect(edge.expression.contains("ReducerPin(moduleName: m0, functionName: m1)"))
    }

    /// A leaf whose raw type has no curated boundary set keeps the generator
    /// Pass 1 uses. Swapping only what is curated is what makes the sweep
    /// composable — the alternative is no edge pass for any carrier that happens
    /// to hold a `Bool`.
    @Test("a leaf with no boundary set keeps its default generator")
    func nonCuratedLeafKeepsItsGenerator() throws {
        let members = [
            MemberSpec(name: "flag", rawType: .bool),
            MemberSpec(name: "count", rawType: .int)
        ]
        let base = try StrategistDispatchEmitter.memberwiseRecipe(
            members: members, carrier: "Pair"
        )
        let edge = try #require(StrategistDispatchEmitter.edgeRecipe(from: base))
        #expect(edge.expression.contains(RawType.bool.generatorExpression))
        #expect(edge.expression.contains("Int.min"))
    }

    /// No curated leaf ⇒ every trial would repeat Pass 1's domain exactly, so
    /// there is nothing to report. The sentinel is the honest answer, and the
    /// renderer says the edge pass did not run.
    @Test("a carrier with no curated leaf keeps the sentinel")
    func allLeavesUncuratedKeepsSentinel() throws {
        let members = [
            MemberSpec(name: "flag", rawType: .bool),
            MemberSpec(name: "ratio", rawType: .double)
        ]
        let base = try StrategistDispatchEmitter.memberwiseRecipe(
            members: members, carrier: "Pair"
        )
        #expect(StrategistDispatchEmitter.boundarySweep(base.expression) == nil)
        #expect(StrategistDispatchEmitter.edgeRecipe(from: base) == nil)
    }

    /// The substitution table is keyed on `RawType.generatorExpression`, so an
    /// entry is only safe if no key is a substring of another key — otherwise
    /// one substitution would corrupt the next. `Gen<Int>.int()` against
    /// `Gen<Int8>.int8()` is the pair that makes this worth asserting rather
    /// than assuming.
    @Test("no substitution key is a substring of another")
    func substitutionKeysAreMutuallyDisjoint() {
        let keys = StrategistDispatchEmitter.boundarySubstitutions.map(\.defaultGenerator)
        #expect(keys.count >= 11, "signed + unsigned integers + String")
        for key in keys {
            let containedIn = keys.filter { $0 != key && $0.contains(key) }
            #expect(containedIn.isEmpty, "`\(key)` is a substring of \(containedIn)")
        }
    }

    /// A raw type with no curated boundary set must not appear in the table at
    /// all — an entry mapping it to itself would report trials over the *same*
    /// domain Pass 1 already covered, which is the "reports success while
    /// asserting nothing new" failure this pass exists to remove.
    @Test("the substitution table omits the raw types with no boundary set")
    func substitutionTableOmitsUncuratedRawTypes() {
        let keys = Set(StrategistDispatchEmitter.boundarySubstitutions.map(\.defaultGenerator))
        #expect(!keys.contains(RawType.bool.generatorExpression))
        #expect(!keys.contains(RawType.double.generatorExpression))
        #expect(!keys.contains(RawType.float.generatorExpression))
    }

    /// Per-slot rotation via `Gen.oneOf` is the follow-up this design declines;
    /// `GeneratorRecipeCompileSafetyTests` bans `Gen.frequency` as a construct
    /// that does not compile in an older language mode, and the heterogeneous
    /// `Gen.oneOf` overload delegates straight to it. Pinned so a later
    /// "broaden the edge pass" edit cannot reach for it without meeting the ban.
    @Test("the swept generator avoids the swift-6.2-only combinators")
    func sweptGeneratorAvoidsBannedCombinators() throws {
        let members = [
            MemberSpec(name: "identity", rawType: .string),
            MemberSpec(name: "count", rawType: .int)
        ]
        let base = try StrategistDispatchEmitter.memberwiseRecipe(
            members: members, carrier: "Decisions"
        )
        let edge = try #require(StrategistDispatchEmitter.edgeRecipe(from: base))
        #expect(!edge.expression.contains("Gen.frequency"))
        #expect(!edge.expression.contains("Gen.oneOf"))
    }

    /// A recursive carrier's expression is a call to a depth-budgeted helper
    /// (`__genNode(3)`), not a composition of leaf generators — there is nothing
    /// to sweep, so the sentinel stands without a special case. The helper
    /// *declaration* does hold leaf generators and is deliberately left alone:
    /// it is emitted once and shared with Pass 1, so sweeping it would change
    /// the domain the VERDICT was taken over.
    @Test("a recursive carrier is excluded by the sweep, not by a special case")
    func recursiveCarrierKeepsSentinel() {
        let helper = "func __genNode(_ budget: Int) -> Generator<Node, AnySequence<Int>> "
            + "{ \(RawType.int.generatorExpression).map(Node.init) }"
        let lifted = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "__genNode(3)",
            carrierTypeName: "Node",
            imports: ["Foundation", "PropertyBased"],
            declarations: [helper]
        )
        #expect(StrategistDispatchEmitter.edgeRecipe(from: lifted) == nil)
    }
}
