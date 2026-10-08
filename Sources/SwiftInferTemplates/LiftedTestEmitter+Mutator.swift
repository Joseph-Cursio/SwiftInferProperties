import SwiftInferCore

/// The laws over a **pure mutator** — a function that returns nothing and changes one value, an
/// `inout` argument or a `mutating` method's `self` — written over copies of the value it changes.
///
/// A mutator has no result to put on either side of `==`, so every law over one has the same
/// shape: draw the value, copy it, apply the mutator to the copy, and compare what it left. The
/// seed names which argument that is (`SeedManifest.Seed.mutates`); the accept path turns it into
/// `mutatedIndex`.
extension LiftedTestEmitter {

    /// Which law to state over what a mutator leaves behind.
    public enum MutatorLaw: Sendable, Equatable {
        /// Two copies given the same inputs end equal — `var a = x; f(&a); var b = x; f(&b); a == b`.
        /// Tautological over a pure mutator, as `f(x) == f(x)` is over a pure function.
        case determinism

        /// Applying it twice changes nothing the first application did not —
        /// `var once = x; f(&once); var twice = once; f(&twice); once == twice`. A conjecture:
        /// `bump()` is a correct mutator that fails it.
        case idempotence
    }

    /// How a mutator law calls its subject.
    public struct MutatorSubject: Sendable, Equatable {
        public let callee: CalleeReference
        /// One generator per drawn argument, the receiver first for an instance method.
        public let generators: [String]
        /// Which drawn argument the mutator writes.
        public let mutatedIndex: Int
        /// `true` for a `mutating` method, called on the copy as `copy.m(…)`; `false` passes the
        /// copy with `&` at `mutatedIndex`.
        public let mutatesReceiver: Bool
        /// Each application is written `_ = try? …`. A throw leaves the copy in whatever state the
        /// mutator reached, and both copies reach it identically, so the comparison stays sound.
        public let isThrows: Bool
        public let argumentTypes: [String]

        public init(
            callee: CalleeReference,
            generators: [String],
            mutatedIndex: Int,
            mutatesReceiver: Bool,
            isThrows: Bool = false,
            argumentTypes: [String] = []
        ) {
            self.callee = callee
            self.generators = generators
            self.mutatedIndex = mutatedIndex
            self.mutatesReceiver = mutatesReceiver
            self.isThrows = isThrows
            self.argumentTypes = argumentTypes
        }
    }

    /// The stub for `law` over `subject`, drawing one value per argument and mutating copies of
    /// the one the subject writes.
    public static func mutatorLaw(_ law: MutatorLaw, subject: MutatorSubject, seed: SamplingSeed.Value) -> String {
        let callee = subject.callee
        let generators = subject.generators
        let mutatedIndex = subject.mutatedIndex
        let drawn = generators.count == 1 ? ["value"] : generators.indices.map { "args.\($0)" }
        func apply(to copy: String) -> String {
            var arguments = drawn
            arguments[mutatedIndex] = subject.mutatesReceiver ? copy : "&\(copy)"
            let call = callee.call(arguments)
            return subject.isThrows ? "_ = try? \(call)" : call
        }
        let original = drawn[mutatedIndex]
        let body: String
        let name: String
        let failure: String
        switch law {
        case .determinism:
            body = "var first = \(original); \(apply(to: "first")); "
                + "var second = \(original); \(apply(to: "second")); return first == second"
            name = "\(callee.identifierName)_isDeterministicOnWhatItMutates"
            failure = "\(callee.displaySignature) is not deterministic — two copies given the same input ended unequal"

        case .idempotence:
            body = "var once = \(original); \(apply(to: "once")); "
                + "var twice = once; \(apply(to: "twice")); return once == twice"
            name = "\(callee.identifierName)_isIdempotent"
            failure = "\(callee.displaySignature) is not idempotent — a second application changed the value"
        }
        let binding = drawn.count == 1
            ? "value"
            : tupleBinding(argumentTypes: subject.argumentTypes, count: drawn.count)
        return makeTestStubExpression(
            testFunctionName: name,
            seed: seed,
            sampleExpression: argumentSample(generators: generators),
            propertyExpression: "{ \(binding) in \(callee.isolated(body)) }",
            failureLabel: failure
        )
    }
}
