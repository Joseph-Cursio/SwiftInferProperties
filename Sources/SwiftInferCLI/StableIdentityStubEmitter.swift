import Foundation
import SwiftInferCore

/// PROTOTYPE — emits a verifier that checks an identity-stability candidate
/// against the kit's `checkStableIdentityPropertyLaws`. Retroactively conforms
/// the imported class to `StableIdentity` (`Mutation`/`apply` derived from the
/// payload-free mutation surface, `makeProbe()` = `Type()`) and drives the
/// mutations, asserting `hashValue` / equality stay invariant.
///
/// Gate (returns `nil`): no payload-free mutation method. `Equatable`/`Hashable`
/// is guaranteed by discovery (only `Hashable` classes are candidates). Uses
/// CONCRETE type names, not `Self` (a final-class witness with the concrete type
/// satisfies the `Self` requirements; `Self` in a class parameter is a
/// covariant-Self error). Works for `final` classes.
public enum StableIdentityStubEmitter {

    public struct Inputs: Equatable, Sendable {
        public let typeName: String
        public let mutationMethods: [String]
        public let moduleName: String
        public let testable: Bool

        public init(typeName: String, mutationMethods: [String], moduleName: String, testable: Bool = false) {
            self.typeName = typeName
            self.mutationMethods = mutationMethods
            self.moduleName = moduleName
            self.testable = testable
        }
    }

    public static func inputs(
        for candidate: StableIdentityCandidate,
        moduleName: String,
        testable: Bool = false
    ) -> Inputs? {
        let methods = candidate.mutationSurface.filter { $0.parameterCount == 0 }.map(\.name)
        var seen: Set<String> = []
        let cases = methods.filter { seen.insert($0).inserted }
        guard !cases.isEmpty else { return nil }
        return Inputs(typeName: candidate.typeName, mutationMethods: cases, moduleName: moduleName, testable: testable)
    }

    public static func emit(_ inputs: Inputs) -> String {
        let cases = inputs.mutationMethods
            .map { "        case \($0)" }
            .joined(separator: "\n")
        let applyArms = inputs.mutationMethods
            .map { "        case .\($0): target.\($0)()" }
            .joined(separator: "\n")
        return """
        // PROTOTYPE — auto-generated StableIdentity verifier. DO NOT EDIT.
        // Type: \(inputs.typeName)  (module: \(inputs.moduleName))
        import Foundation
        import PropertyLawKit
        \(inputs.testable ? "@testable " : "")import \(inputs.moduleName)

        extension \(inputs.typeName): @retroactive StableIdentity {
            public static func makeProbe() -> \(inputs.typeName) { \(inputs.typeName)() }
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
            _ = try await checkStableIdentityPropertyLaws(for: \(inputs.typeName).self)
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
