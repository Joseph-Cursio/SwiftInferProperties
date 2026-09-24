import SwiftInferCore

/// Stub emitters for three laws `verify` already composed and the accept path never wrote:
/// `involution`, `role-postcondition` and `equivalence-relation` (`StubWriterCoverageTests`).
///
/// Each states exactly the law its `verify` composer checks, so a stub on disk and a verify run
/// cannot disagree about what was claimed.
extension LiftedTestEmitter {

    /// `f(f(x)) == x` over the supplied generator — idempotence's shape with the input, not the
    /// first image, on the right. They hold together only for the identity, which is why discovery
    /// withdraws `idempotence` where `involution` names the same declaration.
    public static func involution(
        callee: CalleeReference,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String,
        equalityKind: EqualityKind = .strict
    ) -> String {
        let property = callee.isolated(equalityExpression(
            lhs: callee.call(callee.call("value")),
            rhs: "value",
            kind: equalityKind
        ))
        return withApproximateEqualityHelper(
            makeTestStub(
                testFunctionName: "\(callee.bareName)_isAnInvolution",
                seed: seed,
                generator: generator,
                propertyExpression: property,
                failureLabel: "\(callee.displaySignature) failed involution",
                carrierType: typeName
            ),
            kind: equalityKind
        )
    }

    /// A role-named operation owes its role's guarantee of its **result** — `lowercased` returns
    /// no uppercase character. The role's `violationExpression` is a predicate over `result` that
    /// holds when the guarantee is broken, so the property is its negation; a role without one is
    /// not writable, and `nil` comes back.
    public static func rolePostcondition(
        callee: CalleeReference,
        role: RolePostcondition,
        typeName: String,
        seed: SamplingSeed.Value,
        generator: String
    ) -> String? {
        guard let violation = role.violationExpression else { return nil }
        let body = "let result = \(callee.call("value")); return !(\(violation))"
        return makeTestStub(
            testFunctionName: "\(callee.bareName)_keepsItsPostcondition",
            seed: seed,
            generator: generator,
            propertyExpression: callee.isolated(body),
            failureLabel: "\(callee.displaySignature) broke its postcondition: \(role.law)",
            carrierType: typeName
        )
    }

    /// What an equivalence stub needs: the relation, how its operands are drawn, and — for a
    /// relation held by a receiver, like `equals(_:_:)` on a strategy object — how that receiver is
    /// drawn. The receiver is drawn once per trial and held fixed across the triple, because the
    /// laws are about one relation.
    public struct EquivalenceCall: Sendable {
        public let callee: CalleeReference
        public let operandGenerator: String
        public let receiverGenerator: String?

        public init(callee: CalleeReference, operandGenerator: String, receiverGenerator: String?) {
            self.callee = callee
            self.operandGenerator = operandGenerator
            self.receiverGenerator = receiverGenerator
        }

        /// `a ~ b`, spelled for this relation's shape.
        func relates(_ lhs: String, _ rhs: String) -> String {
            callee.call((receiverGenerator == nil ? [] : ["relation"]) + [lhs, rhs])
        }
    }

    /// Reflexivity, symmetry and transitivity over one drawn triple per trial.
    ///
    /// ⚠ **Transitivity can pass without being checked.** Its antecedent — `a ~ b` and `b ~ c` —
    /// needs two relations to hold at once, which a wide draw almost never produces. So the stub
    /// counts, over the same seed words the check uses, how many triples chain at all, and reports
    /// *not applied* when none does, instead of a green tick that checked nothing (#453). The
    /// caller supplies a tie-dense generator, as the comparator writer does, for the same reason.
    public static func equivalenceRelation(_ call: EquivalenceCall, seed: SamplingSeed.Value) -> String {
        let seedWords = "0x\(hex(seed.stateA)), 0x\(hex(seed.stateB)), "
            + "0x\(hex(seed.stateC)), 0x\(hex(seed.stateD))"
        let receiver = call.receiverGenerator.map { "let relation = (\($0)).run(using: &RNG)" }
        let operands = ["a", "b", "c"].map { "let \($0) = (\(call.operandGenerator)).run(using: &RNG)" }
        let draws = [receiver].compactMap(\.self) + operands
        let slots = (call.receiverGenerator == nil ? [] : ["relation"]) + ["a", "b", "c"]
        let name = call.callee.displaySignature
        // Assembled here and spliced as ONE literal: `Issue.record` takes a `Comment`, and `+`
        // between literals does not type-check there — the first emitted stub failed on that.
        let notApplied = "NOT APPLIED — transitivity: no drawn triple had a ~ b and b ~ c, so it was never "
            + "checked. Reflexivity and symmetry were. Narrow the generator until values relate."
        let failed = "\(escapedForLiteral(name)) is not an equivalence (reflexive, symmetric, transitive) — "
            + "failed at input \\(input). \\(error?.message ?? \"\")"
        return """

        @Test func \(call.callee.bareName)_isAnEquivalence() async {
            let backend = SwiftPropertyBasedBackend()
            let seed = Seed(
                stateA: 0x\(hex(seed.stateA)),
                stateB: 0x\(hex(seed.stateB)),
                stateC: 0x\(hex(seed.stateC)),
                stateD: 0x\(hex(seed.stateD))
            )

        \(equivalenceCoverage(call, seedWords: seedWords, draws: draws, notApplied: notApplied))

            let result = await backend.check(
                trials: 100,
                seed: seed,
                sample: { rng in
        \(draws.map { "            " + $0.replacingOccurrences(of: "RNG", with: "rng") }.joined(separator: "\n"))
                    return (\(slots.joined(separator: ", ")))
                },
                property: { drawn in
        \(slots.indices.map { "            let \(slots[$0]) = drawn.\($0)" }.joined(separator: "\n"))
                    guard \(call.relates("a", "a")) else { return false }
                    guard \(call.relates("a", "b")) == \(call.relates("b", "a")) else { return false }
                    return !(\(call.relates("a", "b")) && \(call.relates("b", "c"))) || \(call.relates("a", "c"))
                }
            )
            if case let .failed(_, _, input, error) = result {
                Issue.record("\(failed)")
            }
        }
        """
    }

    /// Counts the drawn triples that chain (`a ~ b` and `b ~ c`) over the same seed words the check
    /// uses, and reports transitivity as not applied when none did.
    private static func equivalenceCoverage(
        _ call: EquivalenceCall,
        seedWords: String,
        draws: [String],
        notApplied: String
    ) -> String {
        let redraws = draws.map { "        " + $0.replacingOccurrences(of: "RNG", with: "coverageRNG") }
        return """
            // COVERAGE. Transitivity says nothing unless two relations hold at once, so count
            // the triples that chain, over the SAME four seed words the check below uses.
            var coverageRNG = Xoshiro(seed: (\(seedWords)))
            var chained = 0
            for _ in 0 ..< 100 {
        \(redraws.joined(separator: "\n"))
                if \(call.relates("a", "b")) && \(call.relates("b", "c")) { chained += 1 }
            }
            if chained == 0 {
                Issue.record("\(notApplied)")
            }
        """
    }
}
