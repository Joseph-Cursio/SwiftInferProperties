@testable import SwiftInferCLI
import SwiftInferCore
import SwiftInferTemplates
import Testing

/// The accept path writes totality at every arity, and names the cause whenever it does not (#464).
///
/// `predicate` and `input-totality` were held to arity 1, so every instance method and every
/// function of two or more parameters was declined. **The corpus funnel census measured 497
/// entailed laws lost that way — 427 of them instance methods — against 39 entailed laws that
/// ran**, the largest single loss it found.
///
/// Every row here is pinned on **both** sides: the stub builder and `declineReason` must agree,
/// because a subject that emits but carries a decline reason, or declines with none, puts a false
/// sentence in front of the reader — the misattribution #445 and #456 each fixed once.
@Suite("Totality — any arity on the accept path")
struct ArityFreeTotalityTests {

    private static func suggestion(
        template: String = "predicate",
        displayName: String,
        signature: String,
        carrier: String? = nil,
        isInstanceMethod: Bool = false,
        isMutatingMethod: Bool = false
    ) -> Suggestion {
        Suggestion(
            templateName: template,
            evidence: [
                Evidence(
                    displayName: displayName,
                    signature: signature,
                    location: SourceLocation(file: "F.swift", line: 1, column: 1),
                    isInstanceMethod: isInstanceMethod,
                    isMutatingMethod: isMutatingMethod,
                    qualifiedTypeName: carrier
                )
            ],
            score: Score(signals: [Signal(kind: .exactNameMatch, weight: 50, detail: "w")]),
            generator: GeneratorMetadata(source: .todo, confidence: nil, sampling: .notRun),
            explainability: ExplainabilityBlock(whySuggested: [], whyMightBeWrong: []),
            identity: SuggestionIdentity(canonicalInput: "F.swift::\(displayName)")
        )
    }

    /// Emits, and says nothing about declining.
    private static func emits(_ suggestion: Suggestion) throws -> String {
        #expect(StubApplicationArity.declineReason(for: suggestion) == nil)
        return try #require(InteractiveTriage.entailedTemplateStub(for: suggestion))
    }

    /// Declines, and names why.
    private static func declines(_ suggestion: Suggestion) throws -> String {
        #expect(InteractiveTriage.entailedTemplateStub(for: suggestion) == nil)
        return try #require(StubApplicationArity.declineReason(for: suggestion))
    }

    // MARK: - What now emits

    /// The measured witness: SwiftMarkdownWiki's `matchesSearch(_:)`, the walk's best-scoring
    /// subject, declined as `needs 2 arguments (a receiver plus 1), but 'predicate' applies 1`.
    @Test func anInstanceMethodWithAParameterEmits() throws {
        let stub = try Self.emits(Self.suggestion(
            displayName: "matchesSearch(_:)",
            signature: "(GraphNode) -> Bool",
            carrier: "GraphViewModel",
            isInstanceMethod: true
        ))
        #expect(stub.contains("_ = args.0.matchesSearch(args.1); return true"))
        #expect(stub.contains("let arg0 = (GraphViewModel.gen()"), "the receiver is the declaring type, drawn first")
        #expect(stub.contains("let arg1 = (GraphNode.gen()"))
    }

    @Test func aTwoParameterStaticFunctionEmits() throws {
        let stub = try Self.emits(Self.suggestion(
            displayName: "isNeighbor(_:of:)",
            signature: "(Int, Int) -> Bool",
            carrier: "GraphCanvas"
        ))
        #expect(stub.contains("_ = GraphCanvas.isNeighbor(args.0, of: args.1); return true"))
    }

    /// A nullary instance method is the receiver alone, and was also declined before — by the
    /// parameter lookup rather than by arity, under the generic "no stub writeout" sentence.
    @Test func aNullaryInstanceMethodEmitsOverItsReceiver() throws {
        let stub = try Self.emits(Self.suggestion(
            displayName: "isBlank()",
            signature: "() -> Bool",
            carrier: "Line",
            isInstanceMethod: true
        ))
        #expect(stub.contains("{ value in _ = value.isBlank(); return true }"))
    }

    /// **The control.** The unary static subject every existing totality stub came from renders
    /// exactly as the unary emitter always rendered it.
    @Test func aUnaryStaticSubjectIsUnchanged() throws {
        let suggestion = Self.suggestion(
            template: "input-totality",
            displayName: "parse(_:)",
            signature: "(String) -> [WikilinkRef]",
            carrier: "WikilinkParser"
        )
        let expected = LiftedTestEmitter.total(
            callee: CalleeReference(bareName: "parse", qualifier: "WikilinkParser", argumentLabels: [nil]),
            seed: SamplingSeed.derive(from: suggestion.identity),
            generator: LiftedTestEmitter.hostileGenerator(for: "String"),
            isThrowing: false,
            isAsync: false
        )
        #expect(try Self.emits(suggestion) == expected)
    }

    // MARK: - Generators

    /// A receiver is almost always a project type, so the resolver the determinism arm uses is
    /// consulted for it — and **not** for a raw stdlib parameter, which keeps the hostile generator
    /// even when the resolver would answer.
    @Test func theResolverBuildsTheReceiverButNotAStdlibParameter() throws {
        let suggestion = Self.suggestion(
            displayName: "includes(_:)",
            signature: "(String) -> Bool",
            carrier: "Filter",
            isInstanceMethod: true
        )
        let resolver: (String) -> String? = { "Resolved<\($0)>.gen()" }
        let stub = try #require(InteractiveTriage.entailedTemplateStub(for: suggestion, customGenerator: resolver))
        #expect(stub.contains("let arg0 = (Resolved<Filter>.gen()).run(using: &rng)"))
        #expect(stub.contains("Resolved<String>") == false)
        #expect(stub.contains(LiftedTestEmitter.hostileGenerator(for: "String")))
    }

    // MARK: - What still declines, and says why

    @Test func aStaticNullaryFunctionHasNoInput() throws {
        let reason = try Self.declines(Self.suggestion(
            displayName: "isEnabled()",
            signature: "() -> Bool",
            carrier: "FeatureFlags"
        ))
        #expect(reason.contains("takes no arguments"))
    }

    @Test func anInoutParameterCannotBeDrawn() throws {
        let reason = try Self.declines(Self.suggestion(
            displayName: "consume(_:)",
            signature: "(inout Scanner) -> Bool",
            carrier: "Lexer"
        ))
        #expect(reason.contains("inout"))
    }

    @Test func anInstanceMethodWithNoDeclaringTypeHasNoReceiver() throws {
        let reason = try Self.declines(Self.suggestion(
            displayName: "matches(_:)",
            signature: "(String) -> Bool",
            isInstanceMethod: true
        ))
        #expect(reason.contains("no receiver to draw"))
    }

    /// Two parameter types against one recorded label: a call built from that would put an
    /// argument under the wrong label, so it is declined rather than guessed.
    @Test func aLabelAndTypeCountMismatchIsNotGuessed() throws {
        let reason = try Self.declines(Self.suggestion(
            displayName: "check(_:)",
            signature: "(Int, Int) -> Bool",
            carrier: "Rules"
        ))
        #expect(reason.contains("cannot be spelled reliably"))
    }

    @Test func aMutatingMethodStillDeclines() throws {
        let reason = try Self.declines(Self.suggestion(
            displayName: "normalize(_:)",
            signature: "(Int) -> Bool",
            carrier: "Doc",
            isInstanceMethod: true,
            isMutatingMethod: true
        ))
        #expect(reason.contains("mutating"))
    }

    /// **The regression this fix is.** No totality subject is ever told its template applies one
    /// argument.
    @Test func noTotalityDeclineMentionsArity() {
        let subjects = [
            Self.suggestion(displayName: "a(_:)", signature: "(Int) -> Bool", carrier: "T", isInstanceMethod: true),
            Self.suggestion(displayName: "b(_:_:_:)", signature: "(Int, Int, Int) -> Bool", carrier: "T"),
            Self.suggestion(template: "input-totality", displayName: "c(_:)", signature: "(Data) -> X", carrier: "T")
        ]
        for subject in subjects {
            let reason = StubApplicationArity.declineReason(for: subject) ?? ""
            #expect(reason.contains("applies 1") == false, "\(subject.evidence[0].displayName): \(reason)")
        }
    }
}
