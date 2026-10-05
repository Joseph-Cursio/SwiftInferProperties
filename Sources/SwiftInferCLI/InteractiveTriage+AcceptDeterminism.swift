import Foundation
import SwiftInferCore
import SwiftInferTemplates

/// The determinism arm of the accept path.
///
/// Split out of `InteractiveTriage+Accept.swift`, which crossed SwiftLint's file-length cap when
/// #498 threaded argument types through to the emitter. It sits apart for the same reason
/// `+AcceptTotality` does: determinism is the seed-driven generic law rather than a signature
/// template, and it dispatches ahead of the template switch.
extension InteractiveTriage {

    /// The determinism stub for a seeded pure function `f: (P0, …) -> U` — `f(args) == f(args)`
    /// over one generator per argument, with equality keyed off the return type — or `nil` when
    /// its subject cannot be called.
    ///
    /// **Whether it can be called is `SubjectCallPlan`'s answer, not this function's.** The plan
    /// is the one place the call is shaped and declined, and `StubApplicationArity.declineReason`
    /// reads the same `Outcome` — so a stub is written exactly when no reason is given, by
    /// construction rather than by two lists kept in step.
    ///
    /// **Spelled through `CalleeReference`, like every other arm (#465).** This arm took the bare
    /// function name and so wrote `tokenizeLine(value)` for a member of `SwiftTokenizer`; across
    /// the corpus funnel census all 33 determinism stubs that compiled were free functions. A
    /// static member is now qualified, and an instance method draws its receiver from the
    /// declaring type ahead of its parameters — the argument list the totality arm draws
    /// (`arityFreeArgumentTypes`), read through the plan.
    ///
    /// The plan is built with an empty type universe, so a parameter's nested type keeps the
    /// spelling it had; threading the scanned universe into accept is a separate change. Each
    /// argument draws `boundedDeterminismGenerator` first — an `Int` is bounded so unchecked
    /// arithmetic in `f` cannot trap on overflow — then the accept path's resolver. Internal
    /// rather than private so the accept path's behaviour can be tested without writing files.
    static func deterministicStub(
        for suggestion: Suggestion,
        customGenerator: ((String) -> String?)? = nil
    ) -> String? {
        guard let evidence = suggestion.evidence.first,
              case let .plan(plan) = SubjectCallPlan.outcome(for: evidence) else {
            return nil
        }
        let generators = plan.argumentTypes.map { typeName in
            boundedDeterminismGenerator(forTypeName: typeName)
                ?? chooseGenerator(for: suggestion, typeName: typeName, customGenerator: customGenerator)
        }
        return LiftedTestEmitter.deterministic(
            callee: plan.callee,
            generators: generators,
            seed: SamplingSeed.derive(from: suggestion.identity),
            equalityKind: plan.equalityKind,
            isAsync: plan.isAsync,
            isThrows: plan.isThrows,
            // #498 — the types were already in hand here and the emitter never saw them.
            argumentTypes: plan.argumentTypes
        )
    }

    /// The effects the determinism emitter writes around each call: `await` for `async`, and
    /// `try?` for `throws`. One reading, shared by the writer and by its decline, so the decline
    /// fires exactly when the writer would have spelled `try?`.
    ///
    /// **The function's OWN effects** (`FunctionTypeEffects`), not a substring: `" throws"` also
    /// matches a closure parameter's type, and the decline then told the reader a non-throwing
    /// `applyPair(_:_:)` "throws and returns a tuple" while the law's caveats, read from the
    /// scanner's `isThrows`, said it did not. A signature built by `inferenceSignature` spells
    /// exactly the scanner's two flags before its own `->`, so the two now agree. A spelling that
    /// does not parse keeps the substring reading it always had.
    static func determinismEffects(in signature: String) -> (isAsync: Bool, isThrows: Bool) {
        guard let effects = FunctionTypeEffects(signature: signature) else {
            return (signature.contains(" async"), signature.contains(" throws"))
        }
        return (effects.isAsync, effects.isThrows)
    }

    /// Why the determinism law's `==` cannot be written over this subject's result, or `nil` when
    /// it can — keyed on the RESULT type, where every other decline reads the subject's inputs.
    ///
    /// **A tuple never conforms to `Equatable`; Swift defines `==` on tuples of two to six
    /// `Equatable` elements instead** (`TupleResultShape`). So `f(x) == f(x)` over a tuple
    /// compiles, and two shapes of the law do not:
    ///
    /// - **A throwing subject's**, `(try? f(x)) == (try? f(x))`. It compares two `Optional`s of
    ///   the tuple, and `Optional`'s `==` needs its payload to conform — measured with `swiftc` on
    ///   Swift 6.4: *binary operator '==' cannot be applied to two '(text: String, didTruncate:
    ///   Bool)?' operands*. `async throws` is the same case behind an `await`.
    /// - **Any result the spelling alone rules out**: more than six elements, a tuple element, or a
    ///   tuple inside an `Optional` or a collection. SwiftProjectLint is to seed none of these,
    ///   but a hand-written manifest can name any function, so they are refused here too.
    ///
    /// ⚠ **"The spelling" is the limit.** A `typealias` for a tuple reads as its name
    /// (`TupleResultShape`), so a throwing `-> Pair` still gets the `try?` stub, which does not
    /// compile. A non-`Equatable` NOMINAL result is declined at accept by `UnequatableResultGate`,
    /// which holds the scan; an alias for a tuple would need the alias table too, and is not read.
    ///
    /// **The law is still synthesized** (`qualifiesForDeterminism` does not look at the result):
    /// it is tautological, so declining its stub costs no refutable law, while dropping it would
    /// also drop the docstring advice's reference-oracle scaffold, which takes its seed from it.
    ///
    /// The first question `SubjectCallPlan` asks, so `accept` names this cause rather than
    /// "no stub writeout available" (#456). The sentence names no law: the docstring advisory's
    /// reference oracle compares `try?` on both sides too, and is declined by the same plan.
    static func determinismResultDeclineReason(for evidence: Evidence) -> String? {
        let shape = TupleResultShape(signature: evidence.signature)
        if let obstacle = shape.equalityObstacle {
            return "\(evidence.displayName) returns \(obstacle)"
        }
        guard shape.involvesTuple, determinismEffects(in: evidence.signature).isThrows else { return nil }
        let name = evidence.displayName.prefix { $0 != "(" }
        return "\(evidence.displayName) throws and returns a tuple, so the law would compare "
            + "`try? \(name)(…)` on both sides — and an Optional of a tuple has no `==`, because a tuple "
            + "cannot conform to Equatable"
    }
}
