import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// A binary/unary *instance* method emits the receiver-closure call
// expression `{ $0.method(with: $1) }` so a template's positional
// application (`f(a, b)`) becomes `a.method(with: b)` — the shape a binary
// instance operator needs, vs the static `Type.method(a, b)` that doesn't
// type-check. Mutating and free/static functions fall back to the
// label-trampoline form.
@Suite("VerifyCommand — receiver call expression (instance-method emit)")
struct ReceiverCallExpressionTests {

    private typealias VerifyCmd = SwiftInferCommand.Verify

    private func entry(
        function: String,
        isInstanceMethod: Bool,
        isMutatingMethod: Bool = false
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0x1",
            templateName: "commutativity",
            typeName: "Bag",
            score: 60,
            tier: "Likely",
            primaryFunctionName: function,
            location: "/Module.swift:1",
            firstSeenAt: "2026-07-02T00:00:00Z",
            lastSeenAt: "2026-07-02T00:00:00Z",
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod
        )
    }

    @Test("a labeled binary instance method emits the receiver closure")
    func labeledBinaryReceiver() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "combined(with:)", isInstanceMethod: true),
            reference: "Bag.combined",
            bareFunctionName: "combined"
        )
        #expect(call == "{ $0.combined(with: $1) }")
    }

    @Test("an unlabeled binary instance method drops the label")
    func unlabeledBinaryReceiver() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "merged(_:)", isInstanceMethod: true),
            reference: "Bag.merged",
            bareFunctionName: "merged"
        )
        #expect(call == "{ $0.merged($1) }")
    }

    @Test("a nullary instance method emits a receiver call with no args")
    func nullaryReceiver() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "normalized()", isInstanceMethod: true),
            reference: "Bag.normalized",
            bareFunctionName: "normalized"
        )
        #expect(call == "{ $0.normalized() }")
    }

    @Test("a type-qualified bare name is stripped to the method name")
    func qualifiedNameStripped() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "combined(with:)", isInstanceMethod: true),
            reference: "Bag.combined",
            bareFunctionName: "Bag.combined"
        )
        #expect(call == "{ $0.combined(with: $1) }")
    }

    @Test("a mutating instance method falls back to the static/trampoline shape")
    func mutatingFallsBack() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "formUnion(_:)", isInstanceMethod: true, isMutatingMethod: true),
            reference: "Bag.formUnion",
            bareFunctionName: "formUnion"
        )
        // `_`-only labels → labeledCallExpression returns the reference unchanged.
        #expect(call == "Bag.formUnion")
    }

    @Test("a non-instance (free/static) function falls back to the trampoline shape")
    func freeFunctionFallsBack() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "combine(lhs:rhs:)", isInstanceMethod: false),
            reference: "Engine.combine",
            bareFunctionName: "combine"
        )
        #expect(call == "{ Engine.combine(lhs: $0, rhs: $1) }")
    }
}
