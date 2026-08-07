import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The erased self-form arm of `IdempotenceTemplate.typeSymmetrySignal` —
/// `docs/measurements/parsing-catalog-gap.md` §4/§5.
///
/// swift-syntax's formatter is
/// `extension SyntaxProtocol { func formatted(using: BasicFormat = …) -> Syntax }`,
/// and the catalog could not see `format(format(x)) == format(x)` on it at any
/// tier. Two independent gates, not the one the survey first recorded: the
/// return is erased (`Syntax`, not `Self`), and the parameter is defaulted
/// configuration where the self-form arm demanded `parameters.isEmpty`.
///
/// The law is well-formed because `public struct Syntax: SyntaxProtocol` — the
/// return conforms to the carrier, so the result feeds back in. That
/// conformance is the admissibility test, and these tests pin both directions
/// of it.
@Suite("IdempotenceTemplate — erased self-form")
struct ErasedSelfFormTests {

    private func method(
        _ name: String,
        carrier: String,
        returns: String,
        params: [Parameter] = []
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: returns,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "Test.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    private func defaulted(_ type: String, label: String = "using") -> Parameter {
        Parameter(
            label: label, internalName: "cfg", typeText: type,
            isInout: false, hasDefault: true
        )
    }

    private func required(_ type: String, label: String = "using") -> Parameter {
        Parameter(
            label: label, internalName: "cfg", typeText: type,
            isInout: false, hasDefault: false
        )
    }

    /// `Syntax: SyntaxProtocol` — the real relationship, as the corpus index
    /// would record it.
    private let conformances = ["Syntax": Set(["SyntaxProtocol", "SyntaxHashable"])]

    // MARK: - Admission

    @Test("the swift-syntax shape is admitted at lower confidence")
    func swiftSyntaxFormattedIsAdmitted() throws {
        let formatted = method(
            "formatted", carrier: "SyntaxProtocol", returns: "Syntax",
            params: [defaulted("BasicFormat")]
        )
        let signal = try #require(
            IdempotenceTemplate.erasedSelfFormSignal(
                for: formatted, inheritedTypesByName: conformances
            ),
            "SyntaxProtocol.formatted(using:) -> Syntax should be admitted"
        )
        #expect(signal.kind == .typeSymmetrySignature)
        // 25, not the 30 a concrete `T -> T` earns — the survey asked for this
        // as a lower-confidence variant, and the erasure is a real doubt.
        #expect(signal.weight == 25)
        #expect(signal.detail.contains("erased self-form"))
    }

    @Test("end to end: `formatted` reaches Likely, and carries the erasure caveat")
    func formattedReachesLikelyWithCaveat() throws {
        let suggestion = try #require(
            IdempotenceTemplate.suggest(
                for: method(
                    "formatted", carrier: "SyntaxProtocol", returns: "Syntax",
                    params: [defaulted("BasicFormat")]
                ),
                inheritedTypesByName: conformances
            )
        )
        // 25 erased-shape + 40 curated verb `formatted` = 65 → Likely, which is
        // shown on a default run. Deliberately short of Strong.
        #expect(suggestion.score.total == 65)
        #expect(suggestion.score.tier == .likely)
        #expect(
            suggestion.explainability.whyMightBeWrong
                .contains { $0.contains("STATED OVER THE ERASED TYPE") }
        )
    }

    // MARK: - The admissibility test, both directions

    @Test("a return that does NOT conform to the carrier is rejected")
    func nonConformingReturnRejected() {
        // `struct B { func normalized() -> AnyNode }` — the erasure goes to an
        // unrelated type, so `b.normalized().normalized()` does not compile and
        // there is no law to state.
        let mangled = method(
            "mangled", carrier: "NodeProtocol", returns: "AnyNode",
            params: [defaulted("Config")]
        )
        #expect(IdempotenceTemplate.erasedSelfFormSignal(
            for: mangled, inheritedTypesByName: ["AnyNode": Set(["Equatable"])]
        ) == nil)
    }

    @Test("an unresolvable conformance yields nothing rather than a guess")
    func unresolvedConformanceRejected() {
        // The cross-module scoping limit, made explicit: `Syntax` is declared
        // in SwiftSyntax while `formatted` lives in SwiftBasicFormat, so a
        // single-module scan cannot resolve the conformance. Conservative
        // direction — silence, not a guessed suggestion.
        let formatted = method(
            "formatted", carrier: "SyntaxProtocol", returns: "Syntax",
            params: [defaulted("BasicFormat")]
        )
        #expect(IdempotenceTemplate.erasedSelfFormSignal(
            for: formatted, inheritedTypesByName: [:]
        ) == nil)
    }

    @Test("a DECORATOR is rejected — an erasure absorbs itself, a decorator nests")
    func genericDecoratorReturnRejected() {
        // The first tightening measurement forced. Every one of these conforms
        // to its carrier, so the conformance test alone admitted all six — and
        // all six are false, because applying the decorator twice yields
        // `Wrapper<Wrapper<S>>`, a DIFFERENT type from one application, so
        // `f(f(x)) == f(x)` does not even type-check. Subjects verbatim from
        // swift-async-algorithms and swift-nio.
        let decorators: [(name: String, returns: String)] = [
            ("adjacentPairs", "AsyncAdjacentPairsSequence<Self>"),
            ("compacted", "AsyncCompactedSequence<Self, Unwrapped>"),
            ("joined", "AsyncJoinedSequence<Self>"),
            ("removeDuplicates", "AsyncRemoveDuplicatesSequence<Self>"),
            ("splitLines", "NIODecodedAsyncSequence<Self, D>")
        ]
        let carrier = "AsyncSequence"
        for (name, returns) in decorators {
            let summary = method(name, carrier: carrier, returns: returns)
            #expect(
                IdempotenceTemplate.erasedSelfFormSignal(
                    for: summary,
                    inheritedTypesByName: [
                        ProtocolCoverageMap.strippingGenericParameters(returns): Set([carrier])
                    ]
                ) == nil,
                "expected the \(name) decorator rejected"
            )
        }
    }

    @Test("an ACCIDENTAL conformance is rejected — conformance is not erasure")
    func accidentalConformanceRejected() {
        // The second tightening. `String` conforms to swift-argument-parser's
        // `ExpressibleByArgument`, so `defaultValueDescription() -> String`
        // passed the conformance test — but `String` is not that protocol's
        // erased form, it merely satisfies it, and a description of a
        // description is not a fixed point. Two false firings out of four
        // before this gate.
        let summary = method(
            "defaultValueDescription",
            carrier: "ExpressibleByArgument",
            returns: "String"
        )
        #expect(IdempotenceTemplate.erasedSelfFormSignal(
            for: summary,
            inheritedTypesByName: ["String": Set(["ExpressibleByArgument", "Hashable"])]
        ) == nil)
    }

    @Test("both Swift erasure spellings are recognised, and nothing else is")
    func erasureNamingConventions() {
        // `Syntax` / `SyntaxProtocol` — swift-syntax's own, and the motivating
        // case. `AnyShape` / `Shape` — the stdlib/SwiftUI spelling.
        #expect(IdempotenceTemplate.isNamedErasure(of: "SyntaxProtocol", returnType: "Syntax"))
        #expect(IdempotenceTemplate.isNamedErasure(of: "Shape", returnType: "AnyShape"))
        // Not erasures: an accidental conformer, a shared stem, a reversal.
        #expect(!IdempotenceTemplate.isNamedErasure(of: "ExpressibleByArgument", returnType: "String"))
        #expect(!IdempotenceTemplate.isNamedErasure(of: "SyntaxProtocol", returnType: "SyntaxNode"))
        #expect(!IdempotenceTemplate.isNamedErasure(of: "Syntax", returnType: "SyntaxProtocol"))
    }

    @Test("a REQUIRED parameter is an operand, not configuration — rejected")
    func requiredParameterRejected() {
        // `x.normalized()` is not a legal call, so this is not a unary
        // transform of self in any sense.
        let normalized = method(
            "normalized", carrier: "SyntaxProtocol", returns: "Syntax",
            params: [required("BasicFormat")]
        )
        #expect(IdempotenceTemplate.erasedSelfFormSignal(
            for: normalized, inheritedTypesByName: conformances
        ) == nil)
    }

    @Test("mutating and static forms are not self-forms")
    func mutatingAndStaticRejected() {
        for (isMutating, isStatic) in [(true, false), (false, true)] {
            let summary = FunctionSummary(
                name: "formatted",
                parameters: [defaulted("BasicFormat")],
                returnTypeText: "Syntax",
                isThrows: false, isAsync: false,
                isMutating: isMutating, isStatic: isStatic,
                location: SourceLocation(file: "T.swift", line: 1, column: 1),
                containingTypeName: "SyntaxProtocol",
                bodySignals: .empty
            )
            #expect(IdempotenceTemplate.erasedSelfFormSignal(
                for: summary, inheritedTypesByName: conformances
            ) == nil)
        }
    }

    // MARK: - The arm must not shadow the concrete ones

    @Test("a concrete self-form still earns the full 30, not 25")
    func concreteSelfFormUnchanged() throws {
        let concrete = method("normalized", carrier: "Doc", returns: "Doc")
        let signal = try #require(
            IdempotenceTemplate.typeSymmetrySignal(
                for: concrete, inheritedTypesByName: ["Doc": Set(["Equatable"])]
            )
        )
        #expect(signal.weight == 30)
        #expect(!signal.detail.contains("erased"))
    }

    @Test("a concrete free function still earns the full 30")
    func concreteFreeFormUnchanged() throws {
        let free = FunctionSummary(
            name: "normalize",
            parameters: [Parameter(label: nil, internalName: "s", typeText: "String", isInout: false)],
            returnTypeText: "String",
            isThrows: false, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: "Util",
            bodySignals: .empty
        )
        let signal = try #require(IdempotenceTemplate.typeSymmetrySignal(for: free))
        #expect(signal.weight == 30)
    }
}
