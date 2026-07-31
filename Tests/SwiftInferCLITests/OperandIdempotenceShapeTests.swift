import Foundation
import Testing

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// The `a.merge(b).merge(b) == a.merge(b)` idempotence shape — a self-returning,
/// non-mutating instance method that takes **one** operand.
///
/// A carrier reach census over this repo's own index found every remaining
/// `unsupported-carrier` decline on a bare `Self` carrier, and every one of
/// those on this shape. Rebinding `Self` alone moved them from
/// `unsupported-carrier` to `build-failed`: the composer had no argument labels
/// and rendered the static `Decisions.merge`, which is a curried
/// `(Decisions) -> (Decisions) -> Decisions` and does not typecheck against the
/// `(Decisions) -> Decisions` annotation. Both pieces are needed for a verdict.
@Suite("Operand-idempotence shape — a.f(b).f(b) == a.f(b)")
struct OperandIdempotenceShapeTests {

    private static let canonicalSeed = StrategistDispatchEmitter.SeedHex(
        stateA: 0x01, stateB: 0x02, stateC: 0x03, stateD: 0x04
    )

    private static func entry(
        primaryFunctionName: String,
        isInstanceMethod: Bool = true,
        isMutatingMethod: Bool = false,
        isNullary: Bool = false,
        returnsSelfType: Bool = true
    ) -> SemanticIndexEntry {
        SemanticIndexEntry(
            identityHash: "0xTEST",
            templateName: "idempotence",
            typeName: "Decisions",
            score: 55,
            tier: "Likely",
            primaryFunctionName: primaryFunctionName,
            location: "Decisions.swift:1",
            firstSeenAt: "2026-07-30T00:00:00Z",
            lastSeenAt: "2026-07-30T00:00:00Z",
            carrierTypeName: "Self",
            isInstanceMethod: isInstanceMethod,
            isMutatingMethod: isMutatingMethod,
            isNullary: isNullary,
            returnsSelfType: returnsSelfType
        )
    }

    // MARK: - The routing predicate

    @Test("a self-returning instance method taking one operand takes the shape")
    func oneOperandMatches() {
        #expect(SwiftInferCommand.Verify.takesOperandIdempotenceShape(Self.entry(primaryFunctionName: "merge(_:)")))
        #expect(SwiftInferCommand.Verify.takesOperandIdempotenceShape(
            Self.entry(primaryFunctionName: "updated(from:)")
        ))
    }

    /// The nullary self-returning shape already had a composer that chains the
    /// method on the receiver. Routing it here instead would hand that composer
    /// a closure literal and break the method-name extraction it does by
    /// splitting on `.`.
    @Test("the nullary self-returning shape is left to its existing composer")
    func nullaryIsUnaffected() {
        #expect(!SwiftInferCommand.Verify.takesOperandIdempotenceShape(
            Self.entry(primaryFunctionName: "normalized()", isNullary: true)
        ))
    }

    /// Two operands would need a third generated value per trial with no
    /// principled source. Such an entry keeps its previous rendering — and its
    /// previous `build-failed` — rather than acquiring a law that isn't the one
    /// its name claims.
    @Test("more than one operand is deliberately excluded")
    func multipleOperandsExcluded() {
        #expect(!SwiftInferCommand.Verify.takesOperandIdempotenceShape(
            Self.entry(primaryFunctionName: "merge(_:strategy:)")
        ))
    }

    @Test("mutating, static, and non-self-returning shapes are excluded")
    func otherShapesExcluded() {
        #expect(!SwiftInferCommand.Verify.takesOperandIdempotenceShape(
            Self.entry(primaryFunctionName: "merge(_:)", isMutatingMethod: true)
        ))
        #expect(!SwiftInferCommand.Verify.takesOperandIdempotenceShape(
            Self.entry(primaryFunctionName: "merge(_:)", isInstanceMethod: false)
        ))
        #expect(!SwiftInferCommand.Verify.takesOperandIdempotenceShape(
            Self.entry(primaryFunctionName: "merge(_:)", returnsSelfType: false)
        ))
    }

    // MARK: - The emitted stub

    private static func emitOperandShape(functionCall: String) throws -> String {
        try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "idempotence",
                functionCalls: [functionCall],
                seedHex: canonicalSeed,
                trialBudget: .small,
                isInstanceMethod: true,
                isMutatingMethod: false,
                isNullary: false,
                returnsSelfType: true,
                parameterCount: 1
            )
        )
    }

    @Test("the emitted pass draws a receiver AND an operand, then applies both")
    func emitsTwoValueShape() throws {
        let source = try Self.emitOperandShape(functionCall: "{ $0.merge($1) }")
        #expect(source.contains("let value = defaultGenerator.run(using: &rng)"))
        #expect(source.contains("let operand = defaultGenerator.run(using: &rng)"))
        #expect(source.contains("let onceResult = applyOperand(value, operand)"))
        #expect(source.contains("let twiceResult = applyOperand(onceResult, operand)"))
    }

    /// The operand is drawn once and reused. Redrawing it would check
    /// `a.f(b).f(c) == a.f(b)` — not idempotence, and false for any `f` that
    /// does anything at all, so the law would fire on correct code.
    ///
    /// Counted **per pass**: since V1.153 the emitted stub carries two passes
    /// (default + the boundary sweep), each a copy of this same law, so the
    /// whole-source count is two draws × two passes. The invariant under test
    /// is the per-trial one.
    @Test("the operand is held fixed across both applications")
    func operandIsNotRedrawn() throws {
        let source = try Self.emitOperandShape(functionCall: "{ $0.merge($1) }")
        let passes = source.components(separatedBy: "let defaultGenerator").count - 1
        let draws = source.components(separatedBy: "defaultGenerator.run(using: &rng)").count - 1
        #expect(passes == 2, "default pass + boundary pass")
        #expect(draws == 2 * passes, "exactly one receiver draw and one operand draw per trial, per pass")
        #expect(!source.contains("applyOperand(onceResult, defaultGenerator"))
    }

    /// The closure is bound to an explicitly-typed local before use, for the
    /// reason the direct composer documents: applying a closure literal inline
    /// leaves `$0` with nothing to infer from.
    @Test("the call is bound to an explicitly-typed binary local")
    func bindsTypedLocal() throws {
        let source = try Self.emitOperandShape(functionCall: "{ $0.merge($1) }")
        #expect(source.contains("let applyOperand: (Int, Int) -> Int = { $0.merge($1) }"))
    }

    /// Guards the dispatch order in `composeIdempotencePass`: without
    /// `parameterCount == 1` the entry falls through to the direct
    /// `f(f(x))` composer, which is what emitted the uncompilable static form.
    @Test("without the parameter count the entry falls back to the direct shape")
    func parameterCountGatesTheShape() throws {
        let source = try StrategistDispatchEmitter.emit(
            StrategistDispatchEmitter.Inputs(
                carrier: "Int",
                typeShape: nil,
                template: "idempotence",
                functionCalls: ["Decisions.merge"],
                seedHex: Self.canonicalSeed,
                trialBudget: .small,
                isInstanceMethod: true,
                isNullary: false,
                returnsSelfType: true
            )
        )
        #expect(source.contains("let applyOnce: (Int) -> Int = Decisions.merge"))
        #expect(!source.contains("applyOperand"))
    }
}
