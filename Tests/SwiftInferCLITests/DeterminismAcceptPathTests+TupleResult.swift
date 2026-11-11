@testable import SwiftInferCLI
import Testing

// MARK: - A tuple result

/// A seed whose function returns a tuple — the shape SwiftProjectLint starts seeding when it
/// admits a tuple of two to six Equatable elements as an assertable return.
///
/// **A tuple never conforms to `Equatable`; Swift only defines `==` on tuples of two to six
/// elements, each `Equatable`.** So `f(x) == f(x)` over a tuple compiles, and every other shape
/// the law could take over one does not. Measured with `swiftc` on Swift 6.4
/// (`swiftlang-6.4.0.34.1`): a labelled 2-tuple and a 6-tuple compile; a 7-tuple, a nested
/// tuple, `(Int, Int)?`, `[(Int, Int)]` and `[String: (Int, Int)]` each fail with *binary
/// operator '==' cannot be applied*, and so does `(try? f(x)) == (try? f(x))` over a tuple —
/// the form this law takes for a `throws` subject. `(Int, Int)!` and `sending (Int, Int)` compile
/// as the tuple they spell, and their `try?` forms fail as a plain tuple's does.
extension DeterminismAcceptPathTests {

    /// **The shape the linter will seed** (`String.prefix(utf8Bytes:)` in SwiftAssist): a labelled
    /// tuple compared by tuple `==` inside the property closure, which is not a generic context.
    /// `EmittedDeterminismLawSoundnessTests` compiles this shape; this pins that it is the one
    /// written.
    @Test func aTupleResultComparesWithTupleEquality() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "prefix",
            parameters: [Self.parameter("utf8Bytes", "Int")],
            isStatic: false,
            returnType: "(text: String, didTruncate: Bool)",
            containingType: "String"
        ))
        #expect(stub.contains(
            "{ (args: (String, Int)) in "
                + "args.0.prefix(utf8Bytes: args.1) == args.0.prefix(utf8Bytes: args.1) }"
        ))
        #expect(stub.contains("try?") == false)
        #expect(stub.contains("approximatelyEqual") == false)
    }

    /// `equalityKind` matches floating-point type names exactly, so a tuple of `Double`s is
    /// compared strictly — and must be, since the approximate helper is generic over
    /// `FloatingPoint` and a tuple is not one. The NaN this exposes is the TAUTOLOGY header's to
    /// disclose.
    @Test func aTupleOfDoublesIsComparedStrictly() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "split",
            parameters: [Self.parameter(nil, "Double")],
            isStatic: false,
            returnType: "(Double, Double)",
            containingType: nil
        ))
        #expect(stub.contains("{ value in split(value) == split(value) }"))
        #expect(stub.contains("approximatelyEqual") == false)
    }

    /// **The regression the tuple seeds would create.** A throwing subject's law compares
    /// `try? f(x)` on both sides — two `Optional<(json: String, prompt: String)>`, and
    /// `Optional`'s `==` needs its payload to conform to `Equatable`, which a tuple cannot.
    /// Declined at the writer AND named by the decline, so `accept` says why rather than
    /// "no stub writeout available" (#456).
    @Test func aThrowingTupleResultIsDeclinedNamingTheOptional() throws {
        let law = try Self.law(for: Self.summary(
            name: "parseOutput",
            parameters: [Self.parameter(nil, "String")],
            isStatic: true,
            returnType: "(json: String, prompt: String)",
            containingType: "SkillAuthor",
            isThrows: true
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("parseOutput(_:)"))
        #expect(reason.contains("tuple"))
        #expect(reason.contains("Optional"))
        #expect(InteractiveTriage.noStubNote(for: law).contains("no stub writeout available") == false)
    }

    /// The async form is `(try? await f(x))` on both sides — the same `Optional` of a tuple.
    @Test func anAsyncThrowingTupleResultIsDeclinedToo() throws {
        let law = try Self.law(for: Self.summary(
            name: "fetchPair",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: true,
            returnType: "(Int, Int)",
            containingType: "Store",
            isThrows: true,
            isAsync: true
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("Optional"))
    }

    /// **The control.** A throwing subject with a nominal result keeps the `try?` form — the
    /// decline is keyed on the tuple, not on `throws`.
    @Test func aThrowingNominalResultStillWritesTryOnBothSides() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "serialize",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: true,
            returnType: "String",
            containingType: "Engine",
            isThrows: true
        ))
        #expect(stub.contains("(try? Engine.serialize(value)) == (try? Engine.serialize(value))"))
    }

    /// The linter is to admit none of these, and a hand-written manifest can name anything — so
    /// each is declined on its spelling, named, whether or not the subject throws.
    @Test("a tuple shape Swift has no `==` for is declined, and says so", arguments: [
        "(Int, Int, Int, Int, Int, Int, Int)",
        "(Int, (Int, Int))",
        "(Int, Int)?",
        "[(Int, Int)]",
        "[String: (Int, Int)]",
        "Swift.Optional<(Int, Int)>",
        "Swift.Array<(Int, Int)>",
        "ArraySlice<(Int, Int)>",
        "ContiguousArray<(Int, Int)>",
        "sending (Int, (Int, Int))",
    ])
    func aTupleShapeWithNoEqualityIsDeclined(returnType: String) throws {
        let law = try Self.law(for: Self.summary(
            name: "pairs",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: false,
            returnType: returnType,
            containingType: nil
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("pairs(_:)"))
        #expect(reason.contains("tuple"))
    }

    /// Six is the last arity the standard library's `==` overloads cover, so it is written.
    @Test func aSixElementTupleIsWritten() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "spread",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: false,
            returnType: "(Int, Int, Int, Int, Int, Int)",
            containingType: nil
        ))
        #expect(stub.contains("{ value in spread(value) == spread(value) }"))
    }

    /// A function-typed result is not a tuple, even when its parameter list and its own result
    /// are spelled as parentheses — `(Int, Int) -> (Int, Int)` read naively splits at the first
    /// comma into two "components". Whether a closure can be compared is a separate question
    /// (it cannot), and not this rule's to answer.
    @Test func aFunctionTypeResultIsNotMistakenForATuple() throws {
        let law = try Self.law(for: Self.summary(
            name: "makeSwapper",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: false,
            returnType: "(Int, Int) -> (Int, Int)",
            containingType: nil,
            isThrows: true
        ))
        let reason = StubApplicationArity.declineReason(for: law) ?? ""
        #expect(reason.contains("tuple") == false)
    }

    /// **`(Int, Int)!` compares as the tuple**: once `Optional`'s `==` fails to type-check, Swift
    /// force-unwraps both operands and resolves tuple `==` (`swiftc`, Swift 6.4). It was declined
    /// as "a tuple inside an Optional", which the compiler contradicts; `sending` is an ownership
    /// specifier and was never part of the comparison.
    @Test("a tuple result spelled implicitly unwrapped or `sending` is written", arguments: [
        "(Int, Int)!",
        "sending (Int, Int)",
    ])
    func aTupleSpelledAnotherWayIsWritten(returnType: String) throws {
        let stub = try Self.stub(for: Self.summary(
            name: "corners",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: false,
            returnType: returnType,
            containingType: nil
        ))
        #expect(stub.contains("{ value in corners(value) == corners(value) }"))
    }

    /// The throwing form of each is `try?` on both sides — two plain `Optional`s of the tuple,
    /// which `swiftc` rejects for both spellings. `sending` hid the tuple from the classifier, so
    /// that stub was written; `!` read it as wrapped, so the reason named the wrong cause.
    @Test("a throwing tuple result spelled implicitly unwrapped or `sending` is declined as throwing", arguments: [
        "(Int, Int)!",
        "sending (Int, Int)",
    ])
    func aThrowingTupleSpelledAnotherWayIsDeclined(returnType: String) throws {
        let law = try Self.law(for: Self.summary(
            name: "corners",
            parameters: [Self.parameter(nil, "Int")],
            isStatic: false,
            returnType: returnType,
            containingType: nil,
            isThrows: true
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.hasPrefix("corners(_:) throws and returns a tuple"))
        #expect(reason.contains("Optional"))
    }

    /// **A throwing closure PARAMETER is not the subject throwing.** `" throws"` appears in this
    /// signature only inside the closure's type, and reading it as the function's own made accept
    /// say "applyPair(_:_:) throws and returns a tuple" — false, and contradicting the law's own
    /// caveats, which read the scanner's `isThrows`. The subject is still declined, and now for its
    /// real cause: no generator draws a function. It used to read as a label-count mismatch,
    /// because the closure's `->` defeats the parameter-type split (`SubjectCallPlan`).
    @Test func aThrowingClosureParameterIsNotTheSubjectThrowing() throws {
        let law = try Self.law(for: Self.summary(
            name: "applyPair",
            parameters: [Self.parameter(nil, "@Sendable (Int) throws -> Int"), Self.parameter(nil, "Int")],
            isStatic: false,
            returnType: "(Int, Int)",
            containingType: nil
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("throws and returns") == false)
        #expect(reason.contains("function-typed parameter"))
    }
}
