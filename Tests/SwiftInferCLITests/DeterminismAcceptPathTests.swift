@testable import SwiftInferCLI
import SwiftInferCore
import Testing

/// A determinism law about a type member is written as a call that compiles (#465).
///
/// Measured before this fix, across the corpus funnel census: **all 33 determinism stubs that
/// compiled were free functions, and 776 member stubs failed** — static members with
/// `cannot find 'tokenizeLine' in scope`, instance methods the same way with no receiver at all.
/// Two layers had to move: the synthesized evidence kept no declaring type (fixed at the row), and
/// the stub builder took a bare name (fixed here). The first test below runs both.
@Suite("Determinism — the accept path writes a callable stub")
struct DeterminismAcceptPathTests {

    private struct SilentDiagnostics: DiagnosticOutput {
        func writeDiagnostic(_: String) { /* no-op */ }
    }

    /// `isAsync` carries the clock-determinism claim with it, since an async subject earns the
    /// law only under that claim (`qualifiesForDeterminism`).
    static func summary(
        name: String,
        parameters: [Parameter],
        returnType: String = "[Token]",
        isStatic: Bool,
        containingType: String? = "SwiftTokenizer",
        globalActor: String? = nil,
        isThrows: Bool = false,
        isAsync: Bool = false
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "Tokenizer.swift", line: 54, column: 5),
            containingTypeName: containingType,
            bodySignals: .empty,
            isClockDeterministic: isAsync,
            globalActor: globalActor
        )
    }

    static func parameter(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: "arg", typeText: type, isInout: false)
    }

    /// The suggestion `discover --seeds` really produces for a summary — not a hand-built row, so
    /// a regression in either layer fails here.
    static func law(for summary: FunctionSummary) throws -> Suggestion {
        let manifest = SeedManifest(seeds: [
            SeedManifest.Seed(file: "Tokenizer.swift", line: 54, symbol: summary.name, kind: .pureFunction)
        ])
        let laws = SwiftInferCommand.Discover.synthesizeGenericLaws(
            for: manifest,
            summaries: [summary],
            covered: [],
            diagnostics: SilentDiagnostics()
        )
        return try #require(laws.first { $0.templateName == "determinism" })
    }

    private static func stub(for summary: FunctionSummary) throws -> String {
        let law = try law(for: summary)
        #expect(StubApplicationArity.declineReason(for: law) == nil)
        return try #require(InteractiveTriage.deterministicStub(for: law))
    }

    // MARK: - What now compiles

    /// **The census witness, end to end.** Before: `tokenizeLine(value) == tokenizeLine(value)`.
    @Test func aStaticMemberIsQualified() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "tokenizeLine",
            parameters: [Self.parameter(nil, "String")],
            isStatic: true
        ))
        #expect(stub.contains("{ value in SwiftTokenizer.tokenizeLine(value) == SwiftTokenizer.tokenizeLine(value) }"))
    }

    @Test func anInstanceMethodDrawsItsReceiverFromTheDeclaringType() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "render",
            parameters: [Self.parameter("line", "String")],
            isStatic: false,
            containingType: "Highlighter"
        ))
        #expect(stub.contains("let arg0 = (Highlighter.gen()"), "the receiver comes first, from the declaring type")
        // Annotated since #498: a bare `args` cannot be inferred from the sample tuple.
        #expect(stub.contains(
            "{ (args: (Highlighter, String)) in "
                + "args.0.render(line: args.1) == args.0.render(line: args.1) }"
        ))
    }

    @Test func aDeclaredGlobalActorIsHoppedOnce() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "title",
            parameters: [Self.parameter("for", "Int")],
            returnType: "String",
            isStatic: true,
            containingType: "Sidebar",
            globalActor: "MainActor"
        ))
        #expect(stub.contains("await MainActor.run { Sidebar.title(for: value) == Sidebar.title(for: value) }"))
    }

    /// **The control.** A free function renders as it always did, and an `Int` still gets the
    /// bounded generator that keeps unchecked arithmetic from trapping.
    @Test func aFreeFunctionIsUnchanged() throws {
        let stub = try Self.stub(for: Self.summary(
            name: "combine",
            parameters: [Self.parameter(nil, "Int"), Self.parameter("with", "Int")],
            returnType: "Int",
            isStatic: false,
            containingType: nil
        ))
        #expect(stub.contains("let arg0 = (Gen<Int>.int(in: -10_000 ... 10_000)).run(using: &rng)"))
        #expect(stub.contains(
            "{ (args: (Int, Int)) in "
                + "combine(args.0, with: args.1) == combine(args.0, with: args.1) }"
        ))
    }

    /// A project-type receiver the resolver can build is built, rather than left at `.todo`.
    @Test func theResolverBuildsAProjectTypeReceiver() throws {
        let law = try Self.law(for: Self.summary(
            name: "render",
            parameters: [Self.parameter(nil, "String")],
            isStatic: false,
            containingType: "Highlighter"
        ))
        let resolver: (String) -> String? = { $0 == "Highlighter" ? "Gen<Highlighter>.always(Highlighter())" : nil }
        let stub = try #require(InteractiveTriage.deterministicStub(for: law, customGenerator: resolver))
        #expect(stub.contains("let arg0 = (Gen<Highlighter>.always(Highlighter())).run(using: &rng)"))
    }

    // MARK: - What still declines, and says why

    /// Before, a subject the builder could not spell reached the reader as *"no stub writeout
    /// available for template 'determinism'"* — naming a template that has a writer.
    @Test func anUnspellableSubjectNamesItsCause() throws {
        let law = try Self.law(for: Self.summary(
            name: "consume",
            parameters: [Parameter(label: nil, internalName: "scanner", typeText: "inout Scanner", isInout: true)],
            returnType: "Token",
            isStatic: true
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("inout"))
    }
}

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
            returnType: "(text: String, didTruncate: Bool)",
            isStatic: false,
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
            returnType: "(Double, Double)",
            isStatic: false,
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
            returnType: "(json: String, prompt: String)",
            isStatic: true,
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
            returnType: "(Int, Int)",
            isStatic: true,
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
            returnType: "String",
            isStatic: true,
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
        "sending (Int, (Int, Int))"
    ])
    func aTupleShapeWithNoEqualityIsDeclined(returnType: String) throws {
        let law = try Self.law(for: Self.summary(
            name: "pairs",
            parameters: [Self.parameter(nil, "Int")],
            returnType: returnType,
            isStatic: false,
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
            returnType: "(Int, Int, Int, Int, Int, Int)",
            isStatic: false,
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
            returnType: "(Int, Int) -> (Int, Int)",
            isStatic: false,
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
        "sending (Int, Int)"
    ])
    func aTupleSpelledAnotherWayIsWritten(returnType: String) throws {
        let stub = try Self.stub(for: Self.summary(
            name: "corners",
            parameters: [Self.parameter(nil, "Int")],
            returnType: returnType,
            isStatic: false,
            containingType: nil
        ))
        #expect(stub.contains("{ value in corners(value) == corners(value) }"))
    }

    /// The throwing form of each is `try?` on both sides — two plain `Optional`s of the tuple,
    /// which `swiftc` rejects for both spellings. `sending` hid the tuple from the classifier, so
    /// that stub was written; `!` read it as wrapped, so the reason named the wrong cause.
    @Test("a throwing tuple result spelled implicitly unwrapped or `sending` is declined as throwing", arguments: [
        "(Int, Int)!",
        "sending (Int, Int)"
    ])
    func aThrowingTupleSpelledAnotherWayIsDeclined(returnType: String) throws {
        let law = try Self.law(for: Self.summary(
            name: "corners",
            parameters: [Self.parameter(nil, "Int")],
            returnType: returnType,
            isStatic: false,
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
    /// caveats, which read the scanner's `isThrows`. The subject is still declined, for the cause
    /// it was declined for before tuples were looked at: the closure's `->` defeats the
    /// parameter-type split, so the call cannot be spelled.
    @Test func aThrowingClosureParameterIsNotTheSubjectThrowing() throws {
        let law = try Self.law(for: Self.summary(
            name: "applyPair",
            parameters: [Self.parameter(nil, "@Sendable (Int) throws -> Int"), Self.parameter(nil, "Int")],
            returnType: "(Int, Int)",
            isStatic: false,
            containingType: nil
        ))
        #expect(InteractiveTriage.deterministicStub(for: law) == nil)
        let reason = try #require(StubApplicationArity.declineReason(for: law))
        #expect(reason.contains("throws") == false)
        #expect(reason.contains("argument label(s)"))
    }
}
