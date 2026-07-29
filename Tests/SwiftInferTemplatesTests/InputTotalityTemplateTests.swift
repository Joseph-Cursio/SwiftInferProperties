import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// The input-totality law — `docs/parsing-catalog-gap.md` §6 follow-on.
///
/// Reached by *rejecting* the feature that was asked for. Detecting libFuzzer
/// harnesses was measured first: across every repo in reach there are exactly
/// two Swift `LLVMFuzzerTestOneInput` definitions, both compiler test fixtures
/// with no subject, and the real Swift fuzzers (demangler, reflection) are C++.
/// A detector would have fired twice on noise forever.
///
/// The law a harness asserts needs no harness. A function handed arbitrary
/// bytes owes totality regardless, and those are plentiful where harnesses are
/// not: 14 firings across the corpora, concentrated exactly where hostile input
/// arrives — the parser, the socket layer, the config reader.
@Suite("InputTotalityTemplate — functions that interpret untrusted input")
struct InputTotalityTemplateTests {

    private func fn(
        _ name: String,
        params: [(String?, String)],
        returns: String?,
        isThrows: Bool = false,
        carrier: String = "Parser"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params.map {
                Parameter(
                    label: $0.0, internalName: $0.0 ?? "value",
                    typeText: $0.1, isInout: false
                )
            },
            returnTypeText: returns,
            isThrows: isThrows, isAsync: false, isMutating: false, isStatic: true,
            location: SourceLocation(file: "T.swift", line: 1, column: 1),
            containingTypeName: carrier,
            bodySignals: .empty
        )
    }

    // MARK: - The two admission routes

    @Test("raw bytes are content by construction — no verb needed")
    func byteCarrierAdmitted() {
        for type in ["Data", "[UInt8]", "UnsafeRawBufferPointer", "ByteBufferView"] {
            let summary = fn("consume", params: [("data", type)], returns: "Frame")
            #expect(
                InputTotalityTemplate.admission(for: summary) != nil,
                "expected a \(type) parameter admitted"
            )
        }
    }

    @Test("text needs an interpretation verb to carry the claim")
    func textNeedsVerb() {
        // `parse(source: String)` interprets; `describe(source: String)` does not.
        #expect(InputTotalityTemplate.admission(
            for: fn("parse", params: [("source", "String")], returns: "Tree")
        ) != nil)
        #expect(InputTotalityTemplate.admission(
            for: fn("describe", params: [("source", "String")], returns: "Tree")
        ) == nil)
    }

    @Test("the swift-syntax flagship is admitted")
    func swiftSyntaxParseAdmitted() throws {
        let suggestion = try #require(
            InputTotalityTemplate.suggest(
                for: fn("parse", params: [("source", "String")], returns: "SourceFileSyntax")
            )
        )
        // 30 interpreted-text + 10 content label = 40 → Likely, shown by default.
        #expect(suggestion.score.total == 40)
        #expect(suggestion.score.tier == .likely)
    }

    // MARK: - The three measured traps

    @Test("a LOCATION label vetoes the whole function")
    func locationLabelVetoes() {
        // The designed-for case, and it is two functions of identical type shape
        // in one package: SwiftProjectLint's `load(projectRoot: String) ->
        // LintConfiguration` is told WHERE to look, while
        // `parse(fileContent: String) -> [SuppressionDirective]` is handed the
        // content. Only the label separates them.
        #expect(InputTotalityTemplate.admission(
            for: fn("parse", params: [("projectRoot", "String")], returns: "LintConfiguration")
        ) == nil)
        #expect(InputTotalityTemplate.admission(
            for: fn("parse", params: [("fileContent", "String")], returns: "[SuppressionDirective]")
        ) != nil)
        for label in ["path", "pathname", "url", "file", "name"] {
            #expect(InputTotalityTemplate.admission(
                for: fn("parse", params: [(label, "String")], returns: "Tree")
            ) == nil, "expected \(label) vetoed")
        }
    }

    @Test("EGRESS verbs are rejected — the bytes are going out, not coming in")
    func egressVerbsRejected() {
        // Four of the first eighteen firings, and every false one. swift-nio's
        // `write(pointer: UnsafeRawBufferPointer)` and
        // `sendmsg(pointer:destinationPtr:…)` are syscall wrappers whose buffer
        // is data being TRANSMITTED. A type filter cannot tell ingress from
        // egress; only the verb can.
        for name in ["write", "sendmsg", "send", "emit", "flush", "transmit"] {
            #expect(InputTotalityTemplate.admission(
                for: fn(name, params: [("pointer", "UnsafeRawBufferPointer")], returns: "IOResult")
            ) == nil, "expected \(name) rejected as egress")
        }
        // The ingress sibling on the identical type is still admitted.
        #expect(InputTotalityTemplate.admission(
            for: fn("_readCInt", params: [("data", "UnsafeRawBufferPointer")], returns: "CInt")
        ) != nil)
    }

    @Test("`read` and `load` are NOT interpretation verbs")
    func pathFlavouredVerbsExcluded() {
        // Measured as location-takers more often than content-takers:
        // swift-nio's `readlink(_ path: String) -> String`, SwiftProjectLint's
        // `load(projectRoot:)`. Including them would have admitted both.
        #expect(!HostileInputEntryPoints.hasInterpretationVerb("readlink"))
        #expect(!HostileInputEntryPoints.hasInterpretationVerb("loadConfiguration"))
        #expect(HostileInputEntryPoints.hasInterpretationVerb("parseSourceFile"))
        #expect(HostileInputEntryPoints.hasInterpretationVerb("decodeChunk"))
    }

    @Test("verb matching is leading-token, so compounds cannot match by accident")
    func leadingTokenMatching() {
        // A naive substring test reads `String` inside `StringLiteralKind` and
        // `parse` inside `reparseIfNeeded`. This measurement bug actually
        // happened while surveying reach, which is why the match is tokenised.
        #expect(!HostileInputEntryPoints.hasInterpretationVerb("reparseIfNeeded"))
        #expect(!HostileInputEntryPoints.hasEgressVerb("rewriteBuffer"))
    }

    // MARK: - Scoring and caveats

    @Test("raw bytes score above interpreted text — stronger evidence")
    func byteRouteScoresHigher() throws {
        let bytes = try #require(InputTotalityTemplate.suggest(
            for: fn("decode", params: [("data", "Data")], returns: "Frame")
        ))
        let text = try #require(InputTotalityTemplate.suggest(
            for: fn("decode", params: [("text", "String")], returns: "Frame")
        ))
        #expect(bytes.score.total > text.score.total)
    }

    @Test("`throws` raises confidence rather than disqualifying")
    func throwsIsASignalNotAVeto() throws {
        let throwing = try #require(InputTotalityTemplate.suggest(
            for: fn("parse", params: [("source", "String")], returns: "Tree", isThrows: true)
        ))
        let plain = try #require(InputTotalityTemplate.suggest(
            for: fn("parse", params: [("source", "String")], returns: "Tree")
        ))
        #expect(throwing.score.total > plain.score.total)
    }

    @Test("the caveats say what a violation looks like and how to hunt it")
    func caveatsAreActionable() throws {
        let suggestion = try #require(InputTotalityTemplate.suggest(
            for: fn("parse", params: [("source", "String")], returns: "Tree")
        ))
        let caveats = suggestion.explainability.whyMightBeWrong
        // Throwing is the correct answer to bad input, not a failure.
        #expect(caveats.contains { $0.contains("THROWING IS NOT A VIOLATION") })
        // A trap kills the process — that is what a trap is, not a broken harness.
        #expect(caveats.contains { $0.contains("CRASHES THE TEST PROCESS") })
        // And the generator lesson: realistic input never finds this.
        #expect(caveats.contains { $0.contains("REALISTIC INPUT WILL NEVER FIND THIS") })
    }

    @Test("mutating and Void-returning functions are out of scope")
    func shapeGate() {
        var mutatingSummary = fn("parse", params: [("source", "String")], returns: "Tree")
        mutatingSummary = FunctionSummary(
            name: mutatingSummary.name,
            parameters: mutatingSummary.parameters,
            returnTypeText: mutatingSummary.returnTypeText,
            isThrows: false, isAsync: false, isMutating: true, isStatic: false,
            location: mutatingSummary.location,
            containingTypeName: mutatingSummary.containingTypeName,
            bodySignals: .empty
        )
        #expect(InputTotalityTemplate.admission(for: mutatingSummary) == nil)
        #expect(InputTotalityTemplate.admission(
            for: fn("parse", params: [("source", "String")], returns: "Void")
        ) == nil)
    }
}
