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

    private static func summary(
        name: String,
        parameters: [Parameter],
        returnType: String = "[Token]",
        isStatic: Bool,
        containingType: String? = "SwiftTokenizer",
        globalActor: String? = nil
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnType,
            isThrows: false,
            isAsync: false,
            isMutating: false,
            isStatic: isStatic,
            location: SourceLocation(file: "Tokenizer.swift", line: 54, column: 5),
            containingTypeName: containingType,
            bodySignals: .empty,
            globalActor: globalActor
        )
    }

    private static func parameter(_ label: String?, _ type: String) -> Parameter {
        Parameter(label: label, internalName: "arg", typeText: type, isInout: false)
    }

    /// The suggestion `discover --seeds` really produces for a summary — not a hand-built row, so
    /// a regression in either layer fails here.
    private static func law(for summary: FunctionSummary) throws -> Suggestion {
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
        #expect(stub.contains("{ args in args.0.render(line: args.1) == args.0.render(line: args.1) }"))
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
        #expect(stub.contains("{ args in combine(args.0, with: args.1) == combine(args.0, with: args.1) }"))
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
