import Foundation
import SwiftInferCore
import SwiftSyntax

/// Recognition for the `StdlibUnittest` test-closure form — the shape the
/// swift.org stdlib suites are written in, and the reason `TestLifter` read
/// that corpus as empty.
///
/// The two pre-existing rules both key on a *declaration*: an `XCTestCase`
/// method named `test…`, or a function carrying `@Test`. `StdlibUnittest` has
/// neither. A test is a call that takes a trailing closure:
///
/// ```swift
/// SetTestSuite.test("Set.subtracting") { … }                 // direct
///
/// StringTests.test("Comparable: line \(test.loc.line)")       // chained
///   .xfail(test.xfail)
///   .code { … }
/// ```
///
/// Both forms appear in the corpus, so recognition cannot key on the trailing
/// closure's immediate callee — in the chained form that is `.code`, and the
/// `.test("…")` call is several links down the base chain. It also cannot key
/// on the receiver's *name*: the corpus spells it `suite`, `tests`,
/// `SetTestSuite`, `DictionaryTestSuite`, `ArrayTestSuite`, `StringTests`,
/// `mirrors`, `FloatingPoint`, `OptionSetTests`, … — 5,092 call sites with no
/// common prefix. So the rule is structural: **a call with a trailing closure
/// whose callee chain contains a `.test(<string literal>)` call.**
///
/// **Scope.** `TestLifter` only ever scans a tests root, so a non-test
/// `x.test("…") { }` API would have to live inside the test directory to be a
/// false positive. The string-literal first argument is what keeps the rule
/// from matching arbitrary `.test { }` predicate-style calls.
extension TestSuiteParserVisitor {

    /// Emit a summary when `node` is a `StdlibUnittest` test closure.
    func considerStdlibUnittestCall(_ node: FunctionCallExprSyntax) {
        guard let closure = node.trailingClosure,
            let anchor = Self.testCallInCalleeChain(of: node) else {
            return
        }
        let position = node.positionAfterSkippingLeadingTrivia
        let raw = converter.location(for: position)
        summaries.append(TestMethodSummary(
            harness: .stdlibUnittest,
            className: anchor.receiverName,
            methodName: anchor.label,
            // The trailing closure's statements re-wrapped as a block. `Slicer`
            // walks statements and does not read absolute positions (its
            // `location(of:)` is a documented placeholder), so re-parenting is
            // safe here in a way it would not be for a location-sensitive pass.
            body: CodeBlockSyntax(statements: closure.statements),
            location: SwiftInferCore.SourceLocation(
                file: file,
                line: raw.line,
                column: raw.column
            )
        ))
    }

    /// The `.test("label")` call reached by walking down `node`'s callee chain,
    /// with the receiver it was called on.
    ///
    /// Direct form: the chain is one link — `node` itself is the `.test(…)`
    /// call. Chained form: `node` is `.code(…)`, whose base is `.xfail(…)`,
    /// whose base is the `.test(…)` call.
    static func testCallInCalleeChain(
        of node: FunctionCallExprSyntax
    ) -> (receiverName: String?, label: String)? {
        var current: ExprSyntax? = ExprSyntax(node)
        // Bounded so a pathological chain cannot spin; real chains are 1–3.
        for _ in 0 ..< 16 {
            guard let expr = current else { return nil }
            guard let call = expr.as(FunctionCallExprSyntax.self),
                let member = call.calledExpression.as(MemberAccessExprSyntax.self) else {
                return nil
            }
            if member.declName.baseName.text == "test",
                let label = Self.stringLiteralLabel(of: call) {
                return (member.base?.trimmedDescription, label)
            }
            current = member.base
        }
        return nil
    }

    /// The first argument's string-literal text, or `nil` when the first
    /// argument is not a string literal — which is what distinguishes a test
    /// declaration from an arbitrary `.test(…)` call.
    ///
    /// Interpolated labels are common in the corpus
    /// (`"Comparable: line \(test.loc.line)"`). The interpolation is kept
    /// verbatim, delimiters included, since the label is a human-facing name
    /// rather than anything the lifter reasons over — and keeping `\(…)` makes
    /// it visible in output that the segment was not a constant.
    private static func stringLiteralLabel(of call: FunctionCallExprSyntax) -> String? {
        guard let first = call.arguments.first,
            let literal = first.expression.as(StringLiteralExprSyntax.self) else {
            return nil
        }
        let rendered = literal.segments.map { segment -> String in
            switch segment {
            case let .stringSegment(text): return text.content.text
            case let .expressionSegment(expression): return expression.trimmedDescription
            }
        }
        return rendered.joined()
    }
}
