import SwiftInferCore

/// One move of a state-machine pair, as the scaffold spells a call to it.
public struct StateMachineMove: Sendable, Equatable {
    public let name: String
    /// One label per parameter, `nil` for `_`; parallel to `parameterTypes`.
    public let parameterLabels: [String?]
    public let parameterTypes: [String]
    public let isInstanceMethod: Bool
    public let isAsync: Bool
    public let isThrows: Bool

    public init(
        name: String,
        parameterLabels: [String?],
        parameterTypes: [String],
        isInstanceMethod: Bool,
        isAsync: Bool,
        isThrows: Bool
    ) {
        self.name = name
        self.parameterLabels = parameterLabels
        self.parameterTypes = parameterTypes
        self.isInstanceMethod = isInstanceMethod
        self.isAsync = isAsync
        self.isThrows = isThrows
    }

    /// `subject.select(<#Int#>)`, or `Carrier.reset()` for a static move, with `try`/`await`.
    func call(onCarrier carrier: String) -> String {
        let receiver = isInstanceMethod ? "subject" : carrier
        let arguments = zip(parameterLabels, parameterTypes).map { label, type in
            label.map { "\($0): <#\(type)#>" } ?? "<#\(type)#>"
        }
        let prefix = LiftedTestEmitter.replayEffectPrefix(isAsync: isAsync, isThrows: isThrows)
        return "\(prefix)\(receiver).\(name)(\(arguments.joined(separator: ", ")))"
    }
}

extension LiftedTestEmitter {

    /// A scaffold for `state-machine`'s round trip (#478): the two moves, named and spelled, and
    /// an `Issue.record` until a person supplies what the tool cannot.
    ///
    /// ## Why a scaffold and not a law
    ///
    /// The law is `backward ∘ forward == id` over the carrier's state, and three of its inputs are
    /// decisions rather than facts the suggestion carries: **how to build the carrier** — a view
    /// model or store that usually owns I/O, which has to be faked for the moves to change only
    /// in-memory state; **what "the same state" means** — often one property, and the carrier
    /// need not be `Equatable` at all; and **the move's precondition** — `deselect` with nothing
    /// selected is a no-op or an error, and which it is must be decided. A stub that guessed any of
    /// the three would compile against an equality nobody chose, which is #466's failure: a header
    /// stating a law the reader then has to disbelieve.
    ///
    /// ## Why it compiles as written
    ///
    /// Everything the reader supplies is in **comments**; the only live statement is the
    /// `Issue.record`. So the file builds in any test target, fails by design until completed,
    /// and `isScaffold` reads the recorded issue's marker to label it `SCAFFOLD` rather than a law.
    ///
    /// ## Why the pairing had to be fixed first
    ///
    /// Measured before this was written (`normal-form-state-machine-writers.md` §3): **5 of 16
    /// rows named a pair the code does not owe**, and the rule emitted at most one pair per type.
    /// #489 fixed that — 5 false pairs withdrawn, 3 true ones recovered — so a scaffold now names
    /// moves that genuinely undo each other.
    public static func stateMachineScaffold(
        carrier: String,
        forward: StateMachineMove,
        backward: StateMachineMove
    ) -> String {
        let testFunctionName = "\(forward.name)_\(backward.name)_roundTrip"
        let todo = "TODO: complete the state-machine scaffold for \(carrier) — build the subject "
            + "with its I/O faked, choose the state \(forward.name) and \(backward.name) move, then "
            + "apply both and compare"
        return """

        // State-machine scaffold for `\(carrier)`: `\(forward.name)` then `\(backward.name)` should
        // leave the state where it started. swift-infer cannot build the carrier, choose which
        // state counts as unchanged, or decide the move's precondition, so this is a scaffold, not
        // a runnable test — it fails (via Issue.record) until you complete it.
        @Test func \(testFunctionName)() async throws {
            // TODO 1: build the subject with its I/O faked, so the moves change only in-memory state:
            //   let subject = <#\(carrier)(…)#>
            // TODO 2: choose the observable state the moves are about — one Equatable projection,
            //         not the whole object:
            //   let before = subject.<#state#>
            // TODO 3: establish the forward move's precondition if it has one, then go and come back:
            //   \(forward.call(onCarrier: carrier))
            //   \(backward.call(onCarrier: carrier))
            //   #expect(subject.<#state#> == before)
            // THE LAW WORTH MORE: state a predicate true in EVERY reachable state, and check it after
            //   each step of a generated sequence of moves. A round trip on one path passes where an
            //   invariant over fifty random moves reaches a state nobody thought to construct.
            Issue.record("\(todo)")
        }
        """
    }
}
