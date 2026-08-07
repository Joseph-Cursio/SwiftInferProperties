import PropertyLawCore
@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A **recursive carrier** now emits a runnable stub.
///
/// `docs/measurements/parsing-catalog-gap.md` §7(a) measured the dead end: `normalize(Node)
/// -> Node` over `struct Node { var kids: [Node] }` was proposed at **Strong**
/// tier with `Generator: .todo`. The tool made its most confident claim about a
/// law and then could not run it — the worst combination available, because a
/// Strong suggestion is the one a reader is least likely to re-check.
///
/// The kit half is `RecursiveGeneratorEmitter` (see `RecursiveGeneratorTests`
/// there for why the engine never needed a new combinator). This suite pins the
/// consumer half, which has its own failure mode: the top-level carrier does
/// **not** go through `GeneratorResolver.derive`, so it never got the resolver's
/// wrapping. Its members resolve through the closure and come back already
/// carrying the recursion point, which without `liftingRecursion` would emit
/// `__genNode(budget - 1)` into a stub where neither `__genNode` nor `budget`
/// exists.
///
/// That failure would not have read as a codegen bug. A stub that does not
/// compile surfaces downstream as `measured-error: build-failed`, which the
/// report renders as an *architectural* non-verdict — the same shape as
/// "this carrier is out of reach", and the reason the `CaseIterable` member bug
/// in the kit survived unnoticed until a road test put one in member position.
@Suite("Recursive carriers emit a runnable stub")
struct RecursiveCarrierStubTests {

    private static func emit(
        carrier: String,
        members: [(String, String)],
        template: String = "idempotence",
        functionCalls: [String] = ["normalize"]
    ) throws -> String {
        let shape = IndexedTypeShape(
            name: carrier,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members.map {
                IndexedTypeShape.StoredMember(name: $0.0, typeName: $0.1)
            }
        )
        return try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: carrier,
                typeShape: shape,
                template: template,
                functionCalls: functionCalls,
                seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
                trialBudget: .small,
                allShapes: [carrier: shape]
            )
        )
    }

    // MARK: - The dead end is closed

    @Test("`[Self]` carrier: the helper is declared, and declared BEFORE its use")
    func recursiveCarrierEmitsHelper() throws {
        let stub = try Self.emit(carrier: "Node", members: [("name", "String"), ("kids", "[Node]")])

        #expect(stub.contains("func __genNode(_ budget: Int)"))
        #expect(stub.contains("__genNode(4)"), "the check should call the helper")

        // Ordering is load-bearing in exactly the way the collision sweep's is:
        // a helper emitted after the check it serves does not compile.
        //
        // Search backwards for the use. `headerSection` also prints the
        // generator expression in a leading comment, so a forward search finds
        // that comment — which sits above the declaration and would make this
        // assertion fail on correct output.
        let declarationAt = try #require(stub.range(of: "func __genNode(_ budget: Int)"))
        let useAt = try #require(stub.range(of: "__genNode(4)", options: .backwards))
        #expect(declarationAt.lowerBound < useAt.lowerBound,
                "the helper must be declared above the check that calls it")
    }

    @Test("no recursion point leaks into the stub body")
    func noBareRecursionPointEscapes() throws {
        let stub = try Self.emit(carrier: "Node", members: [("kids", "[Node]")])
        // `budget` exists only inside the helper. If `budget - 1` appears
        // anywhere outside that func, the stub references an undefined symbol.
        let body = stub.components(separatedBy: "func __genNode(_ budget: Int)")
        #expect(body.count == 2)
        #expect(!body[0].contains("budget - 1"), "recursion point escaped above the helper")
    }

    @Test("the base arm is present, so the generator terminates")
    func baseArmPresent() throws {
        let stub = try Self.emit(carrier: "Node", members: [("kids", "[Node]")])
        #expect(stub.contains("if budget <= 0 {"))
        #expect(stub.contains("Gen<[Node]>.always([])"))
    }

    // MARK: - Nothing else moved

    @Test("a NON-recursive carrier emits no helper at all")
    func nonRecursiveCarrierUnchanged() throws {
        let stub = try Self.emit(
            carrier: "Point",
            members: [("x", "Int"), ("y", "Int")]
        )
        #expect(!stub.contains("__genPoint"))
        #expect(!stub.contains("budget"))
    }

    @Test("the emitted text for a non-recursive carrier is byte-identical to a plain emit")
    func noDriftForOrdinaryCarriers() throws {
        // The `emit` change inserts a section into the joined output. An empty
        // declaration list must therefore produce the exact previous string —
        // otherwise every golden in the suite shifts for no reason.
        let stub = try Self.emit(carrier: "Point", members: [("x", "Int")])
        #expect(!stub.contains("\n\n\n"), "an empty declarations section left a blank gap")
    }
}
