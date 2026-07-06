import Foundation
import SwiftInferCore

/// PROTOTYPE — emits a standalone verifier that checks a recognized
/// value-semantics candidate via the kit's copy-mutate-compare law. The
/// candidate's corpus lives in its OWN packaged module (path dependency); the
/// verifier `import`s it + `PropertyLawKit`, **retroactively conforms** the
/// imported type to `ValueSemantic` (so the corpus module stays
/// dependency-free), and calls `checkValueSemanticPropertyLaws`.
///
/// The `ValueSemantic` conformance is *derived from discovery*: each payload-free
/// method in the candidate's mutation surface becomes a `Mutation` case, and
/// `apply` dispatches to it (`target.<method>()`). `makeProbe()` is `Type()`
/// (the constructibility assumption; a zero-arg init).
///
/// **Gates (`inputs(for:moduleName:)` returns nil):** a non-`Equatable`
/// candidate (the kit harness compares with `==`) or one with no payload-free
/// mutation method (nothing drivable). Payload-bearing mutations are deferred —
/// the value-generation slice, mirroring the MVVM / `.tca` constructible subset.
///
/// Emits the same `VERIFY_*` marker contract as the algebraic / MVVM stubs
/// (`exit(1)` on FAIL) so `VerifyResultParser` consumes it unchanged. The kit
/// throws `PropertyLawViolation` on a leak → the `catch` emits FAIL, carrying
/// the kit's already-shrunk minimal counterexample in `VERIFY_DEFAULT_INPUT`.
public enum ValueSemanticStubEmitter {

    public struct Inputs: Equatable, Sendable {
        /// The struct being verified (imported from `moduleName`).
        public let typeName: String
        /// Payload-free mutation-method names → the `Mutation` alphabet.
        public let mutationMethods: [String]
        /// The packaged corpus module the verifier imports.
        public let moduleName: String

        public init(typeName: String, mutationMethods: [String], moduleName: String) {
            self.typeName = typeName
            self.mutationMethods = mutationMethods
            self.moduleName = moduleName
        }
    }

    /// Build inputs from a discovered candidate, or `nil` when the candidate
    /// isn't verify-ready (non-Equatable, or no payload-free mutation method).
    public static func inputs(
        for candidate: ValueSemanticCandidate,
        moduleName: String
    ) -> Inputs? {
        guard candidate.equatability == .equatable else { return nil }
        let methods = candidate.mutationSurface
            .filter { $0.parameterCount == 0 }
            .map(\.name)
        // Deterministic, de-duplicated (a name can't be two Mutation cases).
        var seen: Set<String> = []
        let cases = methods.filter { seen.insert($0).inserted }
        guard !cases.isEmpty else { return nil }
        return Inputs(typeName: candidate.typeName, mutationMethods: cases, moduleName: moduleName)
    }

    public static func emit(_ inputs: Inputs) -> String {
        let cases = inputs.mutationMethods
            .map { "        case \($0)" }
            .joined(separator: "\n")
        let applyArms = inputs.mutationMethods
            .map { "        case .\($0): target.\($0)()" }
            .joined(separator: "\n")
        return """
        // PROTOTYPE — auto-generated ValueSemantic verifier. DO NOT EDIT.
        // Type: \(inputs.typeName)  (module: \(inputs.moduleName))
        import Foundation
        import PropertyLawKit
        import \(inputs.moduleName)

        // Retroactive conformance lives in the verifier (not the corpus module),
        // so the packaged corpus stays dependency-free.
        extension \(inputs.typeName): @retroactive ValueSemantic {
            public static func makeProbe() -> Self { \(inputs.typeName)() }
            public enum Mutation: CaseIterable, Sendable {
        \(cases)
            }
            public static func apply(_ mutation: Mutation, to target: inout Self) {
                switch mutation {
        \(applyArms)
                }
            }
        }

        do {
            _ = try await checkValueSemanticPropertyLaws(for: \(inputs.typeName).self)
            print("VERIFY_DEFAULT_RESULT: PASS")
            print("VERIFY_DEFAULT_TRIALS: 1")
            print("VERIFY_EDGE_RESULT: PASS")
            print("VERIFY_EDGE_TRIALS: 0")
            print("VERIFY_EDGE_SAMPLED: 0")
            exit(0)
        } catch {
            print("VERIFY_DEFAULT_RESULT: FAIL")
            print("VERIFY_DEFAULT_TRIAL: 0")
            print("VERIFY_DEFAULT_INPUT: \\(error)")
            exit(1)
        }
        """
    }
}
