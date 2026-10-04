@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// What a determinism law **says** about a tuple result — its caveats and its stub's law-class line.
///
/// "The return type must be Equatable for the law to compile" is false for a tuple twice over: a
/// tuple never is `Equatable`, yet `f(x) == f(x)` over one compiles; and when the subject throws,
/// every element being `Equatable` is still not enough, because the law then compares two
/// `Optional`s of the tuple. A reader told the first sentence would go looking for a conformance
/// that cannot exist.
///
/// **Non-tuple text stays byte-identical**, and the controls below pin it whole rather than by
/// fragment — a reworded fragment check would pass a changed sentence.
@Suite("Determinism — what the law says about a tuple result")
struct DeterminismTupleWordingTests {

    private static let pureCaveat = "Holds only if the function is genuinely pure — a hidden global read or "
        + "nondeterministic dependency would falsify it, which is exactly what the test catches."

    private static let equatableCaveat = "The return type must be Equatable for the law to compile."

    private static let throwsCaveat = "The function throws, so the law compares `try? f(x)` on both sides: "
        + "an input in the throwing domain collapses to `nil == nil` (never a false alarm), and only a value "
        + "difference on a non-throwing input falsifies it."

    private static func law(returnType: String, isThrows: Bool = false) throws -> Suggestion {
        try DeterminismAcceptPathTests.law(for: DeterminismAcceptPathTests.summary(
            name: "prefix",
            parameters: [DeterminismAcceptPathTests.parameter("utf8Bytes", "Int")],
            returnType: returnType,
            isStatic: false,
            containingType: "String",
            isThrows: isThrows
        ))
    }

    // MARK: - Caveats

    @Test func aNonTupleResultsCaveatsAreUnchanged() throws {
        let law = try Self.law(returnType: "[Token]")
        #expect(law.explainability.whyMightBeWrong == [Self.pureCaveat, Self.equatableCaveat])
    }

    @Test func aThrowingNonTupleResultsCaveatsAreUnchanged() throws {
        let law = try Self.law(returnType: "String", isThrows: true)
        #expect(law.explainability.whyMightBeWrong == [Self.pureCaveat, Self.equatableCaveat, Self.throwsCaveat])
    }

    @Test func aTupleResultsCaveatAsksForEquatableElements() throws {
        let caveats = try Self.law(returnType: "(text: String, didTruncate: Bool)").explainability.whyMightBeWrong
        #expect(caveats.contains(Self.equatableCaveat) == false)
        #expect(caveats.contains { $0.hasPrefix("Every element of the returned tuple must be Equatable") })
        #expect(caveats.contains { $0.contains("two to six") && $0.contains("never conforms") })
    }

    /// The `try?` sentence would describe a stub that is never written, so it is replaced by why.
    @Test func aThrowingTupleResultsCaveatSaysNoStubIsWritten() throws {
        let caveats = try Self.law(returnType: "(json: String, prompt: String)", isThrows: true)
            .explainability.whyMightBeWrong
        #expect(caveats.contains(Self.throwsCaveat) == false)
        #expect(caveats.contains { $0.contains("no stub") && $0.contains("Optional") })
    }

    @Test func aTupleShapeWithNoEqualitySaysSoInItsCaveat() throws {
        let caveats = try Self.law(returnType: "(Int, (Int, Int))").explainability.whyMightBeWrong
        #expect(caveats.contains(Self.equatableCaveat) == false)
        #expect(caveats.contains { $0.hasPrefix("No stub can state this law") && $0.contains("tuple") })
    }

    // MARK: - The stub file's law-class line

    @Test func aTupleResultsTautologyLineNamesTheTuple() throws {
        let line = InteractiveTriage.lawClassLine(for: try Self.law(returnType: "(Double, Double)"))
        #expect(line.contains("TAUTOLOGY"))
        #expect(line.contains("(a NaN inside a\n//            collection or tuple, an identity comparison)."))
    }

    @Test func aNonTupleResultsTautologyLineIsUnchanged() throws {
        let line = InteractiveTriage.lawClassLine(for: try Self.law(returnType: "[Double]"))
        #expect(line == """
        // Law class: TAUTOLOGY — true of any pure implementation, so a pass only means no hidden
        //            state showed up in the trials drawn. A failure means either the subject
        //            is not pure, or its result's `==` is not reflexive (a NaN inside a
        //            collection, an identity comparison).

        """)
    }
}
