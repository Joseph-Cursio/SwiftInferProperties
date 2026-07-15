import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

// A binary/unary *instance* method emits the receiver-closure call
// expression `{ (p0: T, p1: T) in p0.method(with: p1) }` so a template's positional
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
        #expect(call == "{ (p0: Bag, p1: Bag) in p0.combined(with: p1) }")
    }

    @Test("an unlabeled binary instance method drops the label")
    func unlabeledBinaryReceiver() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "merged(_:)", isInstanceMethod: true),
            reference: "Bag.merged",
            bareFunctionName: "merged"
        )
        #expect(call == "{ (p0: Bag, p1: Bag) in p0.merged(p1) }")
    }

    @Test("a nullary instance method emits a receiver call with no args")
    func nullaryReceiver() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "normalized()", isInstanceMethod: true),
            reference: "Bag.normalized",
            bareFunctionName: "normalized"
        )
        #expect(call == "{ (p0: Bag) in p0.normalized() }")
    }

    @Test("a type-qualified bare name is stripped to the method name")
    func qualifiedNameStripped() {
        let call = VerifyCmd.receiverCallExpression(
            entry: entry(function: "combined(with:)", isInstanceMethod: true),
            reference: "Bag.combined",
            bareFunctionName: "Bag.combined"
        )
        #expect(call == "{ (p0: Bag, p1: Bag) in p0.combined(with: p1) }")
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

    // MARK: - round-trip half (self-inverse instance method)

    @Test("a round-trip half that IS the primary instance method emits the receiver shape")
    func roundTripHalfReceiverForPrimary() {
        // `flipped()` self-inverse: both halves are the signalled instance method.
        let signal = entry(function: "flipped()", isInstanceMethod: true)
        let forward = VerifyCmd.roundTripHalfCall(entry: signal, typeQualifier: "Bits", bareName: "flipped()")
        let inverse = VerifyCmd.roundTripHalfCall(entry: signal, typeQualifier: "Bits", bareName: "flipped()")
        #expect(forward == "{ (p0: Bag) in p0.flipped() }")
        #expect(inverse == "{ (p0: Bag) in p0.flipped() }")
    }

    @Test("a round-trip half that is NOT the primary keeps the static shape")
    func roundTripHalfStaticForNonPrimary() {
        // Primary (forward) is an instance method, but the inverse half is a
        // different function we have no instance signal for → static shape.
        let signal = entry(function: "encoded()", isInstanceMethod: true)
        let inverse = VerifyCmd.roundTripHalfCall(entry: signal, typeQualifier: "Payload", bareName: "decoded()")
        #expect(inverse == "Payload.decoded")
    }

    @Test("a round-trip half on a non-instance entry keeps the static shape")
    func roundTripHalfStaticForFreeFunction() {
        let signal = entry(function: "encode()", isInstanceMethod: false)
        let call = VerifyCmd.roundTripHalfCall(entry: signal, typeQualifier: "Payload", bareName: "encode()")
        #expect(call == "Payload.encode")
    }
}
