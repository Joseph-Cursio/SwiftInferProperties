import SwiftEffectInference
@testable import SwiftInferCore
import SwiftParser
import SwiftSyntax
import Testing

/// `SoundPurity.soleTrap(of:)` — the trap that is the ONLY refuter, which the impure-subject veto
/// reads to stop withholding `input-totality` from a parser that merely asserts.
///
/// Each `nil` arm is a refuter the single SEI witness could otherwise hide behind a trap; the
/// controls state that the refuter really fires, so a `nil` cannot come from nothing refuting.
@Suite("SoundPurity — a trap that is the only refuter")
struct SoundPuritySoleTrapTests {

    /// The first function declared anywhere in `source`, nested in a type or not.
    private func firstFunction(in source: String) -> FunctionDeclSyntax? {
        Parser.parse(source: source)
            .tokens(viewMode: .sourceAccurate)
            .lazy
            .compactMap { $0.parent?.as(FunctionDeclSyntax.self) }
            .first
    }

    @Test("an assert alone is the sole trap")
    func assertIsTheSoleTrap() throws {
        let function = try #require(firstFunction(in: "func f(_ s: String) -> Int { assert(!s.isEmpty); return 0 }"))
        #expect(SoundPurity.unconfigured.verdict(for: function) == .refuted, "control: the trap refutes")
        #expect(SoundPurity.unconfigured.soleTrap(of: function) == .trap("assert"))
    }

    @Test("a pure function has no sole trap")
    func pureFunctionHasNone() throws {
        let function = try #require(firstFunction(in: "func f(_ s: String) -> Int { s.count }"))
        #expect(SoundPurity.unconfigured.soleTrap(of: function) == nil)
    }

    @Test("a side effect beside the trap is the witness, so there is no sole trap")
    func sideEffectWins() throws {
        let source = "func f(_ s: String) -> Int { assert(true); print(s); return 0 }"
        let function = try #require(firstFunction(in: source))
        #expect(SoundPurity.unconfigured.soleTrap(of: function) == nil)
    }

    /// SEI checks defaults after the body, so the trap would be reported first.
    @Test("any parameter default withholds the answer")
    func defaultArgumentWithholds() throws {
        let source = "func f(_ s: String, n: Int = 1) -> Int { assert(n > 0); return 0 }"
        let function = try #require(firstFunction(in: source))
        #expect(SoundPurity.unconfigured.soleTrap(of: function) == nil)
    }

    /// `ReducerPurityAnalyzer` names no witness, so it must say `.pure` on its own.
    @Test("a hidden static write withholds the answer")
    func reducerRefuterWithholds() throws {
        let function = try #require(firstFunction(in: """
        struct Counter {
            static var calls = 0
            func f(_ s: String) -> Int { Self.calls += 1; assert(true); return 0 }
        }
        """))
        #expect(ReducerPurityAnalyzer.analyze(function) != .pure, "control: the reducer analyzer refutes")
        #expect(SoundPurity.unconfigured.soleTrap(of: function) == nil)
    }
}
