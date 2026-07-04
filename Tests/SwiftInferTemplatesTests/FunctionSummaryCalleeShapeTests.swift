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
        let evidence = Self.summary(name: "sort", isMutating: true, container: "OrderedSet").inferenceEvidence
        #expect(evidence.isInstanceMethod)
        #expect(evidence.isMutatingMethod)
        #expect(evidence.isNullary)
        #expect(evidence.returnsSelfType == false) // Void return
    }

    @Test("nullary non-mutating self-returning (sorted() -> Self) → instance + nullary + returnsSelf")
    func selfReturningNullaryInstance() {
        let evidence = Self.summary(name: "sorted", ret: "Self").inferenceEvidence
        #expect(evidence.isInstanceMethod)
        #expect(evidence.isMutatingMethod == false)
        #expect(evidence.isNullary)
        #expect(evidence.returnsSelfType)
    }

    @Test("self-returning compares up to generic arguments (OrderedSet<Element> on OrderedSet)")
    func selfReturningGenericStripped() {
        let evidence = Self.summary(
            name: "sorted", ret: "OrderedSet<Element>", container: "OrderedSet"
        ).inferenceEvidence
        #expect(evidence.returnsSelfType)
    }

    @Test("arg-bearing instance method is not nullary (stays out of the receiver shapes)")
    func argBearingInstance() {
        let evidence = Self.summary(
            name: "adding", params: [Self.stringParam], ret: "String"
        ).inferenceEvidence
        #expect(evidence.isInstanceMethod)
        #expect(evidence.isNullary == false)
    }

    @Test("free function (no containing type) is not an instance method")
    func freeFunction() {
        let evidence = Self.summary(name: "exp", ret: "Double", container: nil).inferenceEvidence
        #expect(evidence.isInstanceMethod == false)
    }

    @Test("static method is not an instance method even with a containing type")
    func staticMethod() {
        let evidence = Self.summary(name: "make", ret: "Foo", isStatic: true).inferenceEvidence
        #expect(evidence.isInstanceMethod == false)
    }

    @Test("a non-carrier return type is not self-returning (count() -> Int on Foo)")
    func nonSelfReturn() {
        let evidence = Self.summary(name: "count", ret: "Int").inferenceEvidence
        #expect(evidence.returnsSelfType == false)
    }
}
