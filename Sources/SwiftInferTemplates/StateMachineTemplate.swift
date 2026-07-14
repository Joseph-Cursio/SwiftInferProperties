import SwiftInferCore

/// The **state-machine** law: `up ∘ down == id`, and an invariant that survives any action sequence.
///
/// The catalogue's function templates all relate *values*: `f(x)`, `g(f(x))`, `combine(a, b)`. A view
/// model's moves relate nothing — `navigateToFolder(_:)` and `navigateUp()` both return `Void`. What
/// they have in common is the state they mutate, and the property lives there:
///
///     navigate into a folder, then up ⇒ you are exactly where you began
///     and after ANY sequence of moves, `currentPath` still ends in a separator
///
/// The second law is the one worth having, and the one an example test never writes. A round-trip
/// checked on `/a/` → `/a/b/` → `/a/` passes. The invariant checked over a *generated* sequence of
/// fifty moves is what finds the state you never thought to construct.
public enum StateMachineTemplate {

    public static func suggest(for pair: InverseMutatorPair) -> Suggestion? {
        ConstraintRunner.suggest(constraint: makeConstraint(), subject: pair)
    }

    public static func makeConstraint() -> Constraint<InverseMutatorPair> {
        Constraint<InverseMutatorPair>(
            templateName: "state-machine",
            appliesTo: { _ in true },
            signals: { pair in
                [
                    Signal(
                        kind: .inverseMutatorPair,
                        weight: 35,
                        detail: "`\(pair.forward.name)` and `\(pair.backward.name)` move the same "
                            + "state in opposite directions (\(pair.convention.rawValue)) — they owe "
                            + "`\(pair.backward.name) ∘ \(pair.forward.name) == id`"
                    )
                ]
            },
            evidence: { pair in [pair.forward.inferenceEvidence, pair.backward.inferenceEvidence] },
            identity: { pair in
                SuggestionIdentity(
                    canonicalInput: "state-machine|\(pair.forward.containingTypeName ?? "")"
                        + "|\(pair.forward.name)|\(pair.backward.name)"
                )
            },
            carrier: { $0.forward.containingTypeName },
            carrierType: { $0.forward.containingTypeName },
            caveats: { _ in Self.makeCaveats() }
        )
    }

    static func makeCaveats() -> [String] {
        [
            "THE ROUND TRIP is the obvious law — go in, come back, and the state is unchanged — and "
                + "it is the weaker of the two. It rejects a `navigateUp` that trims one path "
                + "component too many, or one too few.",
            "THE INVARIANT IS THE ONE WORTH HAVING: state a predicate that must hold in EVERY "
                + "reachable state (`currentPath` always ends in a separator; it never escapes the "
                + "root), then check it after every step of a GENERATED sequence of moves. A "
                + "round-trip test checked by hand on one path passes; the invariant over fifty "
                + "random moves is what reaches the state you would never have thought to construct.",
            "MIND THE PRECONDITION. `navigateUp` at the root is either a no-op or an error, and which "
                + "one it is must be *decided* rather than discovered: a sequence generator that can "
                + "propose an illegal move needs a guard, or the property fails on the harness rather "
                + "than on the code.",
            "This law does not need the moves to be pure — they may reload from the network. It "
                + "quantifies over the STATE they leave behind, so fake the I/O and assert on the "
                + "state; that is what makes an impure view model property-testable at all."
        ]
    }
}
