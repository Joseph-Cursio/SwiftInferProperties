import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The comparator stub: the kit's strict-weak-ordering suite, over a derived and a tie-dense draw (#475).
///
/// **Why two draws, measured.** Transitivity of incomparability applies only to values that tie on
/// every compared key, and the kit does not guard it — a total order has no ties. Over the resolver's
/// generator for a `struct Item { isFolder: Bool; name: String; size: Int }`, a comparator treating
/// sizes within 1 as equal passed 5 runs of 5 at 1,000 trials; over the tie-dense rewrite it failed
/// 5 of 5 at trial 2. The emitted stub, compiled and run under Swift 6.3, passed a correct comparator
/// and failed all three broken ones — reflexive `<=`, non-transitive `a > b || c < d`, and that one.
@Suite("Strict weak ordering — two draws, delegated to the kit")
struct StrictWeakOrderingEmitterTests {

    private static let itemGenerator = """
    zip(Gen<Bool>.bool(), Gen<Character>.letterOrNumber.string(of: 0...8), Gen<Int>.int())
                .map { Item(isFolder: $0.0, name: $0.1, size: $0.2) }
    """

    // MARK: - The rewrite

    @Test("each literal leaf narrows to a handful of values", arguments: [
        ("Gen<Int>.int()", "Gen<Int>.int(in: 0...4)"),
        ("Gen<UInt64>.uint64()", "Gen<UInt64>.uint64(in: 0...4)"),
        ("Gen<Int8>.int8()", "Gen<Int8>.int8(in: 0...4)"),
        (
            "Gen<Character>.letterOrNumber.string(of: 0...8)",
            "Gen<String?>.element(of: [\"a\", \"b\", \"c\"] as [String]).map { $0! }"
        )
    ])
    func aLeafIsNarrowed(wide: String, dense: String) {
        #expect(LiftedTestEmitter.tieDense(wide) == dense)
    }

    /// A narrowed *continuous* range still almost never draws two equal values, so floating-point
    /// leaves become whole numbers.
    @Test func aFloatingPointLeafBecomesDiscrete() {
        #expect(LiftedTestEmitter.tieDense("Gen<Double>.double(in: -1_000_000...1_000_000)")
            == "Gen<Int>.int(in: 0...4).map { Double($0) }")
    }

    /// Inside a composed generator every leaf is rewritten and the structure is kept.
    @Test func aComposedGeneratorKeepsItsShape() {
        let dense = LiftedTestEmitter.tieDense(Self.itemGenerator)
        #expect(dense.contains("Gen<Int>.int(in: 0...4)"))
        #expect(dense.contains("[\"a\", \"b\", \"c\"]"))
        #expect(dense.contains("Gen<Bool>.bool()"))
        #expect(dense.contains(".map { Item(isFolder: $0.0, name: $0.1, size: $0.2) }"))
    }

    /// A leaf it does not recognise is left alone rather than guessed at.
    @Test func anUnrecognisedLeafIsUntouched() {
        #expect(LiftedTestEmitter.tieDense("Item.gen()") == "Item.gen()")
    }

    // MARK: - The stub

    @Test func eachPassIsAKitCallOverItsGenerator() {
        let stub = LiftedTestEmitter.strictWeakOrdering(
            callee: CalleeReference(bareName: "precedes", qualifier: "Sorting", argumentLabels: [nil, nil]),
            passes: [("wide", Self.itemGenerator), ("dense", LiftedTestEmitter.tieDense(Self.itemGenerator))]
        )
        #expect(stub.contains("@Test func precedes_isAStrictWeakOrdering() async throws {"))
        #expect(stub.components(separatedBy: "try await checkStrictWeakOrderingLaws(").count == 3)
        #expect(stub.components(separatedBy: "by: { Sorting.precedes($0, $1) }").count == 3)
        #expect(stub.contains("over: " + LiftedTestEmitter.tieDense(Self.itemGenerator)))
    }

    /// The note is one comment line per line, so a long explanation never runs past a lint limit
    /// in the reader's project.
    @Test func aMultiLineNoteBecomesOneCommentPerLine() {
        let stub = LiftedTestEmitter.strictWeakOrdering(
            callee: CalleeReference(bareName: "precedes", qualifier: "Sorting", argumentLabels: [nil, nil]),
            passes: [("first line\nsecond line", "Gen<Int>.int()")]
        )
        #expect(stub.contains("    // first line\n    // second line\n"))
    }
}
