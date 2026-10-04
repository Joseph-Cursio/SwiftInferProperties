import SwiftInferCore
import Testing

/// `FunctionTypeEffects` reads the effects a signature declares for the function itself.
///
/// `signature.contains(" throws")` cannot tell the function's own `throws` from one inside a
/// closure parameter or a returned function type — and the determinism accept path used that
/// substring to say a non-throwing function "throws and returns a tuple".
@Suite("FunctionTypeEffects — the function's own async and throws")
struct FunctionTypeEffectsTests {

    @Test("the function's own effects", arguments: [
        ("(Int) -> Int", false, false),
        ("(Int) async -> Int", true, false),
        ("(Int) throws -> (Int, Int)", false, true),
        ("(String, Int) async throws -> (json: String, prompt: String)", true, true),
        ("(inout Scanner) -> Token", false, false)
    ])
    func ownEffects(signature: String, isAsync: Bool, isThrows: Bool) throws {
        let effects = try #require(FunctionTypeEffects(signature: signature))
        #expect(effects.isAsync == isAsync)
        #expect(effects.isThrows == isThrows)
    }

    /// A parameter's or a result's effects are not the function's.
    @Test("effects inside a parameter or the result are not the function's", arguments: [
        "(@Sendable (Int) throws -> Int, Int) -> (Int, Int)",
        "((Int) async throws -> Int) -> Int",
        "(Int) -> () async throws -> Int"
    ])
    func nestedEffectsAreNotTheFunctions(signature: String) throws {
        let effects = try #require(FunctionTypeEffects(signature: signature))
        #expect(effects.isAsync == false)
        #expect(effects.isThrows == false)
    }

    @Test("a spelling that is not a function type has no reading", arguments: [
        "(Int, Int)",
        "(Int) throws -> Int preserving \\.isValid",
        "not a type ((("
    ])
    func noReading(signature: String) {
        #expect(FunctionTypeEffects(signature: signature) == nil)
    }
}
