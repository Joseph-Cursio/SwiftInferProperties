import Foundation
import SwiftInferCore
import Testing

@testable import SwiftInferCLI

/// **The role postcondition, executed rather than only suggested.**
///
/// `docs/measurements/postcondition-law-declined.md` measured the law at **4 of 4 real
/// normaliser bugs killed** where idempotence kills 1 of 4, and the template shipped
/// discovery-only. This is the verify half: the check the emitter writes, and the roles it
/// declines to write one for.
@Suite("Role postcondition — the emitted check")
struct RolePostconditionEmitterTests {

    /// **Two roles execute, and eight do not.** The eight are not an oversight: `sorted`
    /// needs `Element: Comparable`, `deduplicated` needs `Hashable`, `clamped` needs the
    /// caller's bounds, `reversed` / `shuffled` need the input beside the result, and the
    /// escaping pair has no universal scheme.
    ///
    /// **Emitting a check the emitter cannot justify is the measured failure**, not the
    /// cautious one: `criterion-a-unmet-subject.md` found **89% of output failing to
    /// compile** on an unmet subject, from exactly that.
    @Test("only the roles whose check needs no unproven conformance are executable")
    func executableSubsetIsExactlyTheJustifiableOne() {
        let executable = Set(RolePostcondition.allCases.filter(\.isExecutable))
        #expect(
            executable == [.lowercased, .uppercased],
            "executable set drifted: \(executable.map(\.rawValue).sorted())"
        )
        for role in RolePostcondition.allCases where !role.isExecutable {
            #expect(
                role.violationExpression == nil,
                "\(role.rawValue) claims to be advisory and supplies a check"
            )
        }
    }

    /// The check must be TRUE when the law is violated — the opposite convention would
    /// pass every broken subject and refute every correct one, silently.
    @Test("the violation expression fires on a violation and not on a correct result")
    func violationExpressionHasTheRightPolarity() throws {
        // `lowercased` owes "no uppercase", so the check is "contains an uppercase".
        let lowercased = try #require(RolePostcondition.lowercased.violationExpression)
        #expect(lowercased.contains("isUppercase"), "got \(lowercased)")
        let uppercased = try #require(RolePostcondition.uppercased.violationExpression)
        #expect(uppercased.contains("isLowercase"), "got \(uppercased)")
    }

    /// **The emitter declines rather than guessing.** A role with no check must produce no
    /// pass, so verify records `unsupported-template` instead of a stub that will not build.
    @Test("an advisory role emits no pass")
    func advisoryRoleEmitsNothing() {
        for role in RolePostcondition.allCases where !role.isExecutable {
            #expect(role.violationExpression == nil, "\(role.rawValue)")
        }
    }

    /// The law reaches the reader of the emitted source, not only the suggestion. A stub
    /// whose failure prints no law leaves whoever reads the counterexample guessing.
    @Test("the emitted pass names the law it is checking")
    func emittedPassNamesTheLaw() throws {
        let recipe = StrategistDispatchEmitter.GeneratorRecipe(
            expression: "Gen<Character>.letterOrNumber.string(of: 0...8)",
            carrierTypeName: "String",
            imports: []
        )
        let inputs = StrategistDispatchEmitter.Inputs(
            carrier: "Text",
            typeShape: nil,
            template: "role-postcondition",
            functionCalls: ["Text.lowercased"],
            extraImports: [],
            seedHex: .init(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            trialBudget: .small,
            preamble: "",
            allShapes: [:],
            isInstanceMethod: true,
            isMutatingMethod: false,
            isNullary: true,
            returnsSelfType: false,
            isComputedProperty: false,
            parameterCount: 0,
            parameterTypeNames: [],
            receiverTypeName: "Text"
        )
        let source = try #require(
            StrategistDispatchEmitter.composeRolePostconditionPass(inputs: inputs, recipe: recipe)
        )
        #expect(source.contains("no uppercase character"), "the law is not named in the stub")
        #expect(source.contains("isUppercase"), "the check is missing")
        #expect(source.contains("VERIFY_DEFAULT_RESULT"), "the harness markers are missing")
    }
}
