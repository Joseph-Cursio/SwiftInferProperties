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
        let fn = try #require(parse("func add(_ a: Int, _ b: Int) -> Int { a + b }"))
        #expect(SoundPurity.inferredEffect(for: fn) == .pure)
        #expect(SoundPurity.isPure(fn))
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
        let fn = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(fn) == .pure)   // narrow analyzer: "pure"
        #expect(SoundPurity.inferredEffect(for: fn) == nil)   // sound mapping: refuted
    }

    @Test
    func reducerPureButRandom_isRefuted() throws {
        let source = """
        func pick(_ values: [Int]) -> Int {
            values.randomElement() ?? 0
        }
        """
        let fn = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(fn) == .pure)
        #expect(SoundPurity.inferredEffect(for: fn) == nil)
    }

    @Test
    func reducerPureButPartial_isRefuted() throws {
        // Force-unwrap makes the function partial — not total, not pure.
        let source = """
        func firstOf(_ values: [Int]) -> Int { values.first! }
        """
        let fn = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(fn) == .pure)
        #expect(SoundPurity.inferredEffect(for: fn) == nil)
    }

    // MARK: - ReducerPurity refutes (effect-bearing / hidden mutation)

    @Test
    func effectBearing_isRefuted() throws {
        let source = """
        func load(_ id: Int) async -> Int {
            await fetch(id)
        }
        """
        let fn = try #require(parse(source))
        // ReducerPurity sees `await` → effectBearing; and async refutes in
        // PurityInferrer too. Either way, not pure.
        #expect(ReducerPurityAnalyzer.analyze(fn) != .pure)
        #expect(SoundPurity.inferredEffect(for: fn) == nil)
    }

    @Test
    func hiddenMutability_isRefuted() throws {
        let source = """
        func bump(_ id: Int) -> Int {
            Self.counter += 1
            return id
        }
        """
        let fn = try #require(parse(source))
        #expect(ReducerPurityAnalyzer.analyze(fn) == .hiddenMutability)
        #expect(SoundPurity.inferredEffect(for: fn) == nil)
    }
}
