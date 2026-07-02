import PropertyLawCore
import SwiftInferCore
@testable import SwiftInferTemplates
import Testing

/// Callee-shape classification carried on `Evidence` by the
/// `FunctionSummary.inferenceEvidence` projection — the signal the verify
/// emitter uses to choose the instance-method idempotence shape.
@Suite("FunctionSummary.inferenceEvidence — callee-shape signals")
struct FunctionSummaryCalleeShapeTests {

    private static let loc = SourceLocation(file: "T.swift", line: 1, column: 1)

    private static func summary(
        name: String,
        params: [Parameter] = [],
        ret: String? = nil,
        isMutating: Bool = false,
        isStatic: Bool = false,
        container: String? = "Foo"
    ) -> FunctionSummary {
        FunctionSummary(
            name: name,
            parameters: params,
            returnTypeText: ret,
            isThrows: false, isAsync: false, isMutating: isMutating, isStatic: isStatic,
            location: loc,
            containingTypeName: container,
            bodySignals: .empty
        )
    }

    private static let stringParam = Parameter(
        label: nil, internalName: "x", typeText: "String", isInout: false
    )

    @Test("nullary mutating instance method (sort()) → instance + mutating + nullary")
    func mutatingNullaryInstance() {
        let ev = Self.summary(name: "sort", isMutating: true, container: "OrderedSet").inferenceEvidence
        #expect(ev.isInstanceMethod)
        #expect(ev.isMutatingMethod)
        #expect(ev.isNullary)
        #expect(ev.returnsSelfType == false) // Void return
    }

    @Test("nullary non-mutating self-returning (sorted() -> Self) → instance + nullary + returnsSelf")
    func selfReturningNullaryInstance() {
        let ev = Self.summary(name: "sorted", ret: "Self").inferenceEvidence
        #expect(ev.isInstanceMethod)
        #expect(ev.isMutatingMethod == false)
        #expect(ev.isNullary)
        #expect(ev.returnsSelfType)
    }

    @Test("self-returning compares up to generic arguments (OrderedSet<Element> on OrderedSet)")
    func selfReturningGenericStripped() {
        let ev = Self.summary(
            name: "sorted", ret: "OrderedSet<Element>", container: "OrderedSet"
        ).inferenceEvidence
        #expect(ev.returnsSelfType)
    }

    @Test("arg-bearing instance method is not nullary (stays out of the receiver shapes)")
    func argBearingInstance() {
        let ev = Self.summary(
            name: "adding", params: [Self.stringParam], ret: "String"
        ).inferenceEvidence
        #expect(ev.isInstanceMethod)
        #expect(ev.isNullary == false)
    }

    @Test("free function (no containing type) is not an instance method")
    func freeFunction() {
        let ev = Self.summary(name: "exp", ret: "Double", container: nil).inferenceEvidence
        #expect(ev.isInstanceMethod == false)
    }

    @Test("static method is not an instance method even with a containing type")
    func staticMethod() {
        let ev = Self.summary(name: "make", ret: "Foo", isStatic: true).inferenceEvidence
        #expect(ev.isInstanceMethod == false)
    }

    @Test("a non-carrier return type is not self-returning (count() -> Int on Foo)")
    func nonSelfReturn() {
        let ev = Self.summary(name: "count", ret: "Int").inferenceEvidence
        #expect(ev.returnsSelfType == false)
    }
}
