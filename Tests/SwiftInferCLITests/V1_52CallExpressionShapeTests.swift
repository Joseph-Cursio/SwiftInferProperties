import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// V1.52.D — unit tests for the v1.52 cycle (call-expression-shape
// classifier + stderr capture + GenericBindingResolver alignment).
// Four suites, one per workstream (D.1 classify / D.2 pair-resolver
// integration / D.3 stderr / D.4 GenericBindingResolver).

// MARK: - V1.52.D.1 — CallExpressionShape.classify

@Suite("V1.52.A — CallExpressionShape.classify")
struct V1_52CallExpressionShapeTests {

    @Test("operator-named function → .operatorFunction with paren form")
    func operatorClassifiesToOperatorFunction() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "/"
        )
        #expect(result == .operatorFunction(name: "/"))
        #expect(result.rendered == "(/)")
    }

    @Test("free-function name on Complex carrier → .freeFunction (no qualifier)")
    func elementaryFunctionOnComplexClassifiesToFreeFunction() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "exp"
        )
        #expect(result == .freeFunction(name: "exp"))
        #expect(result.rendered == "exp")
    }

    @Test("static method on Int carrier → .staticMethod (default shape)")
    func staticMethodOnIntPreservedAsStaticMethod() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Int",
            bareFunctionName: "binomial"
        )
        #expect(result == .staticMethod(qualifier: "Int", method: "binomial"))
        #expect(result.rendered == "Int.binomial")
    }

    @Test("non-EF carrier with EF-name → .staticMethod (no free-function lift)")
    func nonEFCarrierWithEFNameStaysStatic() {
        // `OrderedSet` is not in `freeFunctionMap`; even though `log`
        // is an EF surface name, the classifier must NOT lift it.
        let result = CallExpressionShape.classify(
            typeQualifier: "OrderedSet",
            bareFunctionName: "log"
        )
        #expect(result == .staticMethod(qualifier: "OrderedSet", method: "log"))
        #expect(result.rendered == "OrderedSet.log")
    }

    @Test("multi-character operator → .operatorFunction with full paren form")
    func multiCharacterOperatorClassifiesCorrectly() {
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "<<"
        )
        #expect(result == .operatorFunction(name: "<<"))
        #expect(result.rendered == "(<<)")
    }

    @Test("Complex carrier with non-EF name (_relaxedMul) → .staticMethod")
    func complexCarrierWithNonEFNameStaysStatic() {
        // `_relaxedMul` isn't operator-named (underscore is not an
        // operator char) and isn't in the ElementaryFunctions surface,
        // so it must classify as a static method. Regression guard
        // for the V1.52.A risk #1 over-classification scenario.
        let result = CallExpressionShape.classify(
            typeQualifier: "Complex",
            bareFunctionName: "_relaxedMul"
        )
        #expect(result == .staticMethod(qualifier: "Complex", method: "_relaxedMul"))
        #expect(result.rendered == "Complex._relaxedMul")
    }

    @Test("Double + log → .freeFunction (V1.51.C monotonicity-on-Double path)")
    func doubleWithLogClassifiesToFreeFunction() {
        // The cycle-48 monotonicity-on-Double picks land here — the
        // resolver previously built `Double.log` which compiled but
        // produced the wrong runtime shape; V1.52.A emits `log` so
        // the swift-numerics global `log<T: ElementaryFunctions>(_:)`
        // overload is the actual call site.
        let result = CallExpressionShape.classify(
            typeQualifier: "Double",
            bareFunctionName: "log"
        )
        #expect(result == .freeFunction(name: "log"))
        #expect(result.rendered == "log")
    }

    @Test("isOperatorName edge cases (empty / mixed / digit)")
    func isOperatorNameEdgeCases() {
        // Empty: false (otherwise vacuous `allSatisfy` would return true).
        #expect(CallExpressionShape.isOperatorName("") == false)
        // Mixed alphanumeric + operator char: false.
        #expect(CallExpressionShape.isOperatorName("+1") == false)
        #expect(CallExpressionShape.isOperatorName("foo+") == false)
        // Pure operator chars: true.
        #expect(CallExpressionShape.isOperatorName("+") == true)
        #expect(CallExpressionShape.isOperatorName("==") == true)
        #expect(CallExpressionShape.isOperatorName("!=") == true)
        // Identifier with underscore: false (underscore is not an op char).
        #expect(CallExpressionShape.isOperatorName("_relaxedMul") == false)
    }
}

// MARK: - V1.52.D.2 — Pair-resolver integration

@Suite("V1.52.A — Pair-resolver call-site integration")
struct V1_52PairResolverIntegrationTests {

    private static func entry(
        template: String,
        carrier: String,
        primary: String,
        hash: String = "0xCAFEBABEDEADBEEF"
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: hash,
            templateName: template,
            typeName: carrier,
            score: 60,
            tier: "Strong",
            primaryFunctionName: primary,
            location: "/Module.swift:1",
            firstSeenAt: "2026-05-13T00:00:00Z",
            lastSeenAt: "2026-05-13T00:00:00Z"
        )
    }

    @Test("round-trip on Complex with exp(_:) emits free-function form")
    func roundTripExpEmitsFreeFunction() throws {
        let result = try RoundTripPairResolver.resolve(
            Self.entry(template: "round-trip", carrier: "Complex<Double>", primary: "exp(_:)")
        )
        #expect(result.forwardCall == "exp")
        #expect(result.inverseCall == "log")
    }

    @Test("commutativity on Complex with operator name `+` emits paren form")
    func commutativityOperatorEmitsParenForm() throws {
        let result = try CommutativityPairResolver.resolve(
            Self.entry(template: "commutativity", carrier: "Complex<Double>", primary: "+(z:w:)")
        )
        #expect(result.functionCall == "(+)")
    }

    @Test("associativity on Complex with operator name `*` emits paren form")
    func associativityOperatorEmitsParenForm() throws {
        let result = try AssociativityPairResolver.resolve(
            Self.entry(template: "associativity", carrier: "Complex<Double>", primary: "*(z:w:)")
        )
        #expect(result.functionCall == "(*)")
    }

    @Test("monotonicity on Double with log(onePlus:) emits free-function form")
    func monotonicityLogOnePlusEmitsFreeFunction() throws {
        let result = try MonotonicityPairResolver.resolve(
            Self.entry(template: "monotonicity", carrier: "Double", primary: "log(onePlus:)")
        )
        #expect(result.functionCall == "log")
    }
}

// MARK: - V1.52.D.3 — Stderr capture in parse-error detail

@Suite("V1.52.B — Stderr capture in VerifyResultParser parse-error path")
struct V1_52StderrCaptureTests {

    private static func output(
        exitCode: Int32,
        stdout: String = "",
        stderr: String = ""
    ) -> VerifierSubprocess.Output {
        VerifierSubprocess.Output(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    @Test("parse-error with non-empty stderr surfaces stderr in the detail string")
    func parseErrorIncludesStderrWhenPresent() {
        // Cycle-48 evidence: subprocess exit 6 SIGABRT with empty
        // stdout; the Swift-runtime trap reason ends up on stderr.
        let raw = Self.output(
            exitCode: 6,
            stdout: "",
            stderr: "Fatal error: NaN encountered in normalization\n"
                + "Stack dump:\nFrame 0: SwiftInferVerifier.main"
        )
        guard case let .error(reason) = VerifyResultParser.parse(raw) else {
            Issue.record("expected .error outcome")
            return
        }
        #expect(reason.contains("exited with code 6"))
        #expect(reason.contains("stderr (last 5 lines, pipe-joined):"))
        #expect(reason.contains("Fatal error: NaN encountered in normalization"))
    }

    @Test("parse-error with empty stderr preserves pre-V1.52.B detail format")
    func parseErrorOmitsStderrWhenEmpty() {
        // When stderr is empty, the detail string should not include
        // a stderr segment — backward-compatible with v1.51 formatting.
        let raw = Self.output(
            exitCode: 2,
            stdout: "Some output\nVERIFY_DEFAULT_RESULT: ???",
            stderr: ""
        )
        guard case let .error(reason) = VerifyResultParser.parse(raw) else {
            Issue.record("expected .error outcome")
            return
        }
        #expect(reason.contains("exited with code 2"))
        #expect(reason.contains("stdout (last 5 lines, pipe-joined):"))
        #expect(reason.contains("stderr") == false)
    }

    @Test("very long stderr line is truncated to 200 chars with ellipsis")
    func parseErrorTruncatesLongStderrLine() {
        // 250-char single-line stderr; expect a 200-char prefix + …
        let longLine = String(repeating: "X", count: 250)
        let raw = Self.output(exitCode: 6, stderr: longLine)
        guard case let .error(reason) = VerifyResultParser.parse(raw) else {
            Issue.record("expected .error outcome")
            return
        }
        // The 200-char-prefix-plus-ellipsis form is what `pipeJoinedTail`
        // produces — verify the ellipsis appears (= truncation fired).
        #expect(reason.contains("…"))
        // And the original 250-char "X..." run shouldn't appear verbatim.
        #expect(reason.contains(longLine) == false)
    }
}

// MARK: - V1.52.D.4 — GenericBindingResolver expansion

@Suite("V1.52.C — GenericBindingResolver carrier-name expansion")
struct V1_52GenericBindingExpansionTests {

    @Test("ChunkedByCollection.Index binds to Int")
    func chunkedByCollectionIndexBindsToInt() {
        #expect(GenericBindingResolver.resolve("ChunkedByCollection.Index") == "Int")
        #expect(GenericBindingResolver.bound("ChunkedByCollection.Index") == "Int")
    }

    @Test("ChunkedOnCollection.Index binds to Int")
    func chunkedOnCollectionIndexBindsToInt() {
        #expect(GenericBindingResolver.resolve("ChunkedOnCollection.Index") == "Int")
    }

    @Test("ChunkedByLazyCollection.Index binds to Int")
    func chunkedByLazyCollectionIndexBindsToInt() {
        #expect(GenericBindingResolver.resolve("ChunkedByLazyCollection.Index") == "Int")
    }

    @Test("OrderedSet.Index placeholder binds to Int")
    func orderedSetIndexBindsToInt() {
        #expect(GenericBindingResolver.resolve("OrderedSet.Index") == "Int")
    }

    @Test("V1.47.D + V1.51.A bindings still resolve (regression guard)")
    func priorBindingsStillResolve() {
        // V1.47.D bindings (cycle-44 layer).
        #expect(GenericBindingResolver.resolve("Base.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Base.Element") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Index") == "Int")
        #expect(GenericBindingResolver.resolve("Self.Element") == "Int")
        #expect(GenericBindingResolver.resolve("Iterator.Element") == "Int")
        // V1.51.A bare→qualified.
        #expect(GenericBindingResolver.resolve("Complex") == "Complex<Double>")
    }

    @Test("unknown carrier name passes through unchanged")
    func unknownCarrierPassesThrough() {
        #expect(GenericBindingResolver.resolve("ChunkedByCollection.SubSequence") == nil)
        #expect(GenericBindingResolver.bound("ChunkedByCollection.SubSequence")
            == "ChunkedByCollection.SubSequence")
        // OrderedDictionary.Index has no V1.52.C entry — passes through.
        #expect(GenericBindingResolver.resolve("OrderedDictionary.Index") == nil)
    }
}
