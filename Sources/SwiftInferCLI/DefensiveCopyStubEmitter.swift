import Foundation
import SwiftInferCore

/// PROTOTYPE — emits a verifier that checks a defensive-copy candidate against
/// the kit's `checkDefensiveCopyPropertyLaws`. Retroactively conforms the
/// imported class to `DefensiveCopy`: `copyUnderTest()` calls the discovered
/// copy method, `Mutation`/`apply` are derived from the payload-free mutation
/// surface (classes mutate in place — no `inout`), `makeProbe()` is `Type()`.
///
/// Gates (return `nil`): non-`Equatable` (the harness compares with `==`) or no
/// payload-free mutation method. Same `VERIFY_*` marker contract + minimal-repro
/// extraction as the value-semantics emitter. Works for `final` classes
/// (`copyUnderTest() -> Self` returns the copy method's result as `Self`).
public enum DefensiveCopyStubEmitter {

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        public let copyMethodName: String
        public let mutationMethods: [String]
        public let moduleName: String
        public let testable: Bool

        public init(
            typeName: String,
            copyMethodName: String,
            mutationMethods: [String],
            moduleName: String,
            testable: Bool = false
        ) {
            self.typeName = typeName
            self.copyMethodName = copyMethodName
            self.mutationMethods = mutationMethods
            self.moduleName = moduleName
            self.testable = testable
        }
    }

    public static func inputs(
        for candidate: DefensiveCopyCandidate,
        moduleName: String,
        testable: Bool = false
    ) -> Inputs? {
        guard candidate.equatability == .equatable else { return nil }
        let methods = candidate.mutationSurface.filter { $0.parameterCount == 0 }.map(\.name)
        var seen: Set<String> = []
        let cases = methods.filter { seen.insert($0).inserted }
        guard !cases.isEmpty else { return nil }
        return Inputs(
            typeName: candidate.typeName,
            copyMethodName: candidate.copyMethodName,
            mutationMethods: cases,
            moduleName: moduleName,
            testable: testable
        )
    }

    public static func emit(_ inputs: Inputs) -> String {
        let cases = inputs.mutationMethods
            .map { "        case \($0)" }
            .joined(separator: "\n")
        let applyArms = inputs.mutationMethods
            .map { "        case .\($0): target.\($0)()" }
            .joined(separator: "\n")
        return """
        // PROTOTYPE — auto-generated DefensiveCopy verifier. DO NOT EDIT.
        // Type: \(inputs.typeName)  (module: \(inputs.moduleName))
        import Foundation
        import PropertyLawKit
        \(inputs.testable ? "@testable " : "")import \(inputs.moduleName)

        // Concrete return/parameter types (not `Self`) — a `final` class witness
        // with the concrete type satisfies the `Self` protocol requirements, and
        // `Self` in a class parameter position is a covariant-Self error.
        extension \(inputs.typeName): @retroactive DefensiveCopy {
            public static func makeProbe() -> \(inputs.typeName) { \(inputs.typeName)() }
            public func copyUnderTest() -> \(inputs.typeName) { \(inputs.copyMethodName)() }
            public enum Mutation: CaseIterable, Sendable {
        \(cases)
            }
            public static func apply(_ mutation: Mutation, to target: \(inputs.typeName)) {
                switch mutation {
        \(applyArms)
                }
            }
        }

        do {
            _ = try await checkDefensiveCopyPropertyLaws(for: \(inputs.typeName).self)
            print("VERIFY_DEFAULT_RESULT: PASS")
            print("VERIFY_DEFAULT_TRIALS: 1")
            print("VERIFY_EDGE_RESULT: PASS")
            print("VERIFY_EDGE_TRIALS: 0")
            print("VERIFY_EDGE_SAMPLED: 0")
            exit(0)
        } catch let violation as PropertyLawViolation {
            let repro = violation.results.compactMap(\\.counterexample).first ?? "\\(violation)"
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            print("VERIFY_DEFAULT_INPUT: \\(repro)")
            exit(1)
        } catch {
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            print("VERIFY_DEFAULT_INPUT: \\(error)")
            exit(1)
        }
        """
    }
}
