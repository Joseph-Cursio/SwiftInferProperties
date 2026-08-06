import Foundation
@testable import SwiftInferCLI
import Testing

/// A function with no owning type must render as a bare call.
///
/// `resolveFunctionCalls` spells the absence of an owning type as
/// `entry.typeName ?? "(none)"`, and the renderer treated that sentinel as if it
/// were a type name — emitting `(none).isSwiftUIView(candidate)`, which fails to
/// compile with *cannot find 'none' in scope*.
///
/// Worth recording how long it hid: every affected pick took a
/// `StructDeclSyntax` or `FunctionCallExprSyntax`, so until SwiftSyntax carriers
/// could be generated they all declined at `unsupported-carrier` and never
/// reached this renderer at all. One fixed gate is what exposes the next, and a
/// bug behind a gate is indistinguishable from no bug.
@Suite("CallExpressionShape — a free function has no receiver")
struct CallExpressionShapeFreeFunctionTests {

    // MARK: - The sentinel

    @Test("the `(none)` sentinel classifies as a free function")
    func sentinelIsFreeFunction() {
        let shape = CallExpressionShape.classify(
            typeQualifier: "(none)", bareFunctionName: "isSwiftUIView"
        )
        #expect(shape == .freeFunction(name: "isSwiftUIView"))
    }

    @Test("the `(none)` sentinel renders without a qualifier")
    func sentinelRendersBare() {
        let rendered = CallExpressionShape.classify(
            typeQualifier: "(none)", bareFunctionName: "isSwiftUIView"
        ).rendered
        #expect(rendered == "isSwiftUIView")
        #expect(!rendered.contains("none"))
        #expect(!rendered.contains("."))
    }

    /// An empty qualifier means the same thing the sentinel does. Accepting both
    /// keeps the fix at the choke point rather than coupling it to one caller's
    /// spelling of "nothing".
    @Test("an empty qualifier classifies as a free function")
    func emptyQualifierIsFreeFunction() {
        let shape = CallExpressionShape.classify(typeQualifier: "", bareFunctionName: "helper")
        #expect(shape == .freeFunction(name: "helper"))
    }

    @Test("render(_:_:) produces a bare call for the sentinel")
    func renderProducesBareCall() {
        let rendered = CallExpressionShape.render(
            typeQualifier: "(none)", bareFunctionName: "isForEachCollectionSafeForSelfID(_:)"
        )
        #expect(rendered == "isForEachCollectionSafeForSelfID(_:)")
    }

    // MARK: - No collateral damage

    /// The whole classifier is a strict refinement of `"\(qualifier).\(name)"`,
    /// and this fix must not widen it: a real owning type still qualifies.
    @Test("a real type qualifier still renders as a static method")
    func realQualifierUnchanged() {
        let shape = CallExpressionShape.classify(
            typeQualifier: "ProtocolExemption", bareFunctionName: "isTestDoubleName"
        )
        #expect(shape == .staticMethod(qualifier: "ProtocolExemption", method: "isTestDoubleName"))
        #expect(shape.rendered == "ProtocolExemption.isTestDoubleName")
    }

    /// Operator classification is checked *before* the sentinel, and must stay
    /// there: an operator on no type is still an operator, and `(+)` is the form
    /// that compiles.
    @Test("an operator name still wins over the sentinel")
    func operatorBeatsSentinel() {
        let shape = CallExpressionShape.classify(typeQualifier: "(none)", bareFunctionName: "+")
        #expect(shape == .operatorFunction(name: "+"))
        #expect(shape.rendered == "(+)")
    }

    /// A type genuinely *named* in the corpus is not the sentinel, even if a
    /// reader might mistake it for one. Only the exact spelling is special.
    @Test("a qualifier that merely contains \"none\" is not the sentinel")
    func lookalikeQualifierIsNotSentinel() {
        let shape = CallExpressionShape.classify(
            typeQualifier: "NoneOfTheAbove", bareFunctionName: "matches"
        )
        #expect(shape == .staticMethod(qualifier: "NoneOfTheAbove", method: "matches"))
    }
}
