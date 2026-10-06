import Foundation
import SwiftEffectInference
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// Idea #4 step 2 — soundness tests for `SoundPurity`, which maps a function's
/// purity onto `SwiftEffectInference.Effect` by taking the **meet** of two
/// refutation analyzers: SIP's `ReducerPurityAnalyzer` (TCA effects + hidden
/// mutation) and SEI's `PurityInferrer` (I/O / nondeterminism / totality).
///
/// The headline cases are the ones where `ReducerPurity.pure` alone would be
/// **unsound** — a body with no TCA effect that nonetheless logs, reads a
/// clock, or traps. The composition must refute `.pure` there.
@Suite("SoundPurity — sound Effect.pure mapping (Idea #4 step 2)")
struct SoundPurityTests {

    private func parse(_ source: String) -> FunctionDeclSyntax? {
        let tree = Parser.parse(source: source)
        for stmt in tree.statements where stmt.item.is(FunctionDeclSyntax.self) {
            return stmt.item.as(FunctionDeclSyntax.self)
        }
        return nil
    }

    // MARK: - Both analyzers agree it is pure

    @Test
    func transparentFunction_isPure() throws {
        let function = try #require(parse("func add(_ a: Int, _ b: Int) -> Int { a + b }"))
        #expect(SoundPurity.unconfigured.inferredEffect(for: function) == .pure)
        #expect(SoundPurity.unconfigured.isPure(function))
    }

    // MARK: - The soundness cases — ReducerPurity.pure, but NOT Effect.pure

    @Test
    func reducerPureButLogs_isRefuted() throws {
        // No TCA effect and no hidden mutation, so ReducerPurityAnalyzer alone
        // returns `.pure`. But `print` is a side effect — `Effect.pure` must be
        // refuted. This is exactly the case the meet exists to catch.
        let source = """
        func tally(_ values: [Int]) -> Int {
            print("tallying")
            return values.reduce(0, +)
        }
        """
        let function = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(function) == .pure)   // narrow analyzer: "pure"
        #expect(SoundPurity.unconfigured.inferredEffect(for: function) == nil)   // sound mapping: refuted
    }

    @Test
    func reducerPureButRandom_isRefuted() throws {
        let source = """
        func pick(_ values: [Int]) -> Int {
            values.randomElement() ?? 0
        }
        """
        let function = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(function) == .pure)
        #expect(SoundPurity.unconfigured.inferredEffect(for: function) == nil)
    }

    @Test
    func reducerPureButPartial_isRefuted() throws {
        // Force-unwrap makes the function partial — not total, not pure.
        let source = """
        func firstOf(_ values: [Int]) -> Int { values.first! }
        """
        let function = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(function) == .pure)
        #expect(SoundPurity.unconfigured.inferredEffect(for: function) == nil)
    }

    // MARK: - ReducerPurity refutes (effect-bearing / hidden mutation)

    @Test
    func effectBearing_isRefuted() throws {
        let source = """
        func load(_ id: Int) async -> Int {
            await fetch(id)
        }
        """
        let function = try #require(parse(source))
        // ReducerPurity sees `await` → effectBearing; and async refutes in
        // PurityInferrer too. Either way, not pure.
        #expect(ReducerPurityAnalyzer.analyze(function) != .pure)
        #expect(SoundPurity.unconfigured.inferredEffect(for: function) == nil)
    }

    @Test
    func hiddenMutability_isRefuted() throws {
        let source = """
        func bump(_ id: Int) -> Int {
            Self.counter += 1
            return id
        }
        """
        let function = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(function) == .hiddenMutability)
        #expect(SoundPurity.unconfigured.inferredEffect(for: function) == nil)
    }

    // MARK: - Configured with construction facts

    /// Every answer goes through the one configured inferrer — the whole-domain question as well
    /// as the verdict, and the getter's verdict too. `make` and `sample` name nothing impure; the
    /// `UUID` they mint is in `Item`'s stored default, which only the table can see.
    @Test
    func constructionFacts_refuteEveryAnswer() throws {
        let tree = Parser.parse(source: """
        struct Item { let id = UUID(); let title: String }
        func make(_ title: String) -> Item { Item(title: title) }
        struct Shelf { let title: String; var sample: Item { Item(title: title) } }
        """)
        let function = try #require(tree.statements.lazy.compactMap { $0.item.as(FunctionDeclSyntax.self) }.first)
        let shelf = try #require(tree.statements.lazy.compactMap { $0.item.as(StructDeclSyntax.self) }.last)
        let getters = shelf.memberBlock.members.compactMap {
            $0.decl.as(VariableDeclSyntax.self)?.bindings.first?.accessorBlock
        }
        let getter = try #require(getters.first)
        let configured = SoundPurity(constructionFacts: .build(from: [tree]))

        #expect(SoundPurity.unconfigured.isPure(function), "control: without the table `make` reads pure")
        #expect(configured.inferredEffect(for: function) == nil)
        #expect(!configured.isPure(function))
        #expect(configured.verdict(for: function) == .refuted)
        #expect(SoundPurity.unconfigured.verdict(forGetter: getter) == .pure, "control: the getter alone reads pure")
        #expect(configured.verdict(forGetter: getter) == .refuted, "the getter is judged without the table")
        #expect(configured.constructionFacts.refutedTypeNames == ["Item"])
    }
}
