import Foundation
@testable import SwiftInferCore
import Testing

/// V1.36.A — `Constraint<Subject>` data-model tests. Field defaults,
/// generic Subject type-checking, closure invocation.
@Suite("Constraint — V1.36.A data model")
struct ConstraintTests {

    // MARK: - Field defaults

    @Test("V1.36.A — carrier default returns nil for templates that don't wire it")
    func carrierDefaultIsNil() {
        let constraint = Constraint<String>(
            templateName: "test-template",
            appliesTo: { _ in true },
            signals: { _ in [] },
            evidence: { _ in [] },
            identity: { _ in SuggestionIdentity(canonicalInput: "test") }
        )
        #expect(constraint.carrier("subject") == nil)
    }

    @Test("V1.36.A — caveats default returns empty array")
    func caveatsDefaultIsEmpty() {
        let constraint = Constraint<String>(
            templateName: "test-template",
            appliesTo: { _ in true },
            signals: { _ in [] },
            evidence: { _ in [] },
            identity: { _ in SuggestionIdentity(canonicalInput: "test") }
        )
        #expect(constraint.caveats("subject").isEmpty)
    }

    @Test("V1.36.A — carrier override flows through")
    func carrierOverride() {
        let constraint = Constraint<String>(
            templateName: "test-template",
            appliesTo: { _ in true },
            signals: { _ in [] },
            evidence: { _ in [] },
            identity: { _ in SuggestionIdentity(canonicalInput: "test") },
            carrier: { subject in "Type-\(subject)" }
        )
        #expect(constraint.carrier("Foo") == "Type-Foo")
    }

    // MARK: - Generic Subject types

    @Test("V1.36.A — Constraint can be parameterised on FunctionSummary")
    func constraintGenericOverFunctionSummary() {
        let summary = FunctionSummary(
            name: "test",
            parameters: [],
            returnTypeText: nil,
            isThrows: false, isAsync: false, isMutating: false, isStatic: false,
            location: SourceLocation(file: "x.swift", line: 1, column: 1),
            containingTypeName: "Foo",
            bodySignals: .empty
        )
        let constraint = Constraint<FunctionSummary>(
            templateName: "x",
            appliesTo: { $0.name == "test" },
            signals: { _ in [] },
            evidence: { _ in [] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") }
        )
        #expect(constraint.appliesTo(summary))
    }

    // MARK: - Closure invocation

    @Test("V1.36.A — appliesTo gate is invoked exactly once per Subject")
    func appliesToInvocation() {
        let invocations = LockedCounter()
        let constraint = Constraint<Int>(
            templateName: "x",
            appliesTo: { value in
                invocations.increment()
                return value > 0
            },
            signals: { _ in [] },
            evidence: { _ in [] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") }
        )
        #expect(constraint.appliesTo(5))
        #expect(!constraint.appliesTo(-1))
        #expect(invocations.value == 2)
    }

    @Test("V1.36.A — signals closure builds the signal list per Subject")
    func signalsBuildList() {
        let constraint = Constraint<Int>(
            templateName: "x",
            appliesTo: { _ in true },
            signals: { value in
                [Signal(kind: .typeSymmetrySignature, weight: value, detail: "value=\(value)")]
            },
            evidence: { _ in [] },
            identity: { _ in SuggestionIdentity(canonicalInput: "x") }
        )
        let signals = constraint.signals(42)
        #expect(signals.count == 1)
        #expect(signals[0].weight == 42)
    }

    @Test("V1.36.A — identity closure produces deterministic SuggestionIdentity")
    func identityIsDeterministic() {
        let constraint = Constraint<String>(
            templateName: "x",
            appliesTo: { _ in true },
            signals: { _ in [] },
            evidence: { _ in [] },
            identity: { subject in
                SuggestionIdentity(canonicalInput: "stable-input|\(subject)")
            }
        )
        let id1 = constraint.identity("foo")
        let id2 = constraint.identity("foo")
        #expect(id1 == id2, "same Subject should produce same identity")
        let id3 = constraint.identity("bar")
        #expect(id1 != id3, "different Subject should produce different identity")
    }
}

/// Trivial thread-safe counter for the appliesTo-invocation test.
/// (Mirrors what we'd use in a `@Sendable` closure capture without
/// pulling in a heavier sync framework.)
private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}
