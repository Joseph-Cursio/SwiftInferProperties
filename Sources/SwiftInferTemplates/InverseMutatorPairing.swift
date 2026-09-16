import SwiftInferCore

/// Two void-returning mutators on one type that move a state machine in opposite directions.
///
/// `navigateToFolder(_:)` and `navigateUp()` are not a function pair in any shape the catalogue knew.
/// Neither returns anything. Neither takes the other's output. They are joined only by what they *do*
/// to the state they share — and that is exactly the property:
///
///     up ∘ down == id            navigate into a folder, then up, and you are where you began
///
/// plus a class invariant that must survive **any** sequence of them (`currentPath` always ends in a
/// separator; it never escapes the root).
///
/// This shape is why the existing pairing types could not find it. `FunctionPairing` looks for
/// `A -> B` and `B -> A`; `DualStylePairing` looks for `mutating op` / `op -> Self`. A state machine's
/// moves are *`(inout State) -> Void`*, and their relationship is expressible only over the state they
/// both touch.
public struct InverseMutatorPair: Sendable, Equatable {

    /// The move that goes *in* — `navigateToFolder(_:)`. Takes an argument: which way to descend.
    public let forward: FunctionSummary

    /// The move that goes *back* — `navigateUp()`. Takes none: there is only one way up.
    public let backward: FunctionSummary

    /// The direction convention that matched, rendered so the reader can audit it.
    public let convention: Convention

    public init(forward: FunctionSummary, backward: FunctionSummary, convention: Convention) {
        self.forward = forward
        self.backward = backward
        self.convention = convention
    }

    /// The name conventions that mark a direction pair.
    ///
    /// **This template keys on names, and unlike the others it has to.** A comparator is identifiable
    /// from its signature; two `-> Void` mutators are not — `navigateUp()` and `logout()` have
    /// identical shapes. What makes one the inverse of the other is *what they mean*, and meaning is
    /// carried in the name. Recorded as a first-class field so a reader can see which convention
    /// fired and reject it, rather than being asked to trust an invisible heuristic.
    public enum Convention: String, Sendable, Equatable {
        /// `navigateTo…` / `navigateUp`, `push` / `pop`, `open` / `close`.
        case directionalVerb
        /// `enter` / `exit`, `descend` / `ascend`, `select` / `deselect`.
        case enterExit
    }
}

/// Finds inverse mutator pairs among the scanned functions.
public enum InverseMutatorPairing {

    /// One direction convention: the stem that goes in, the stem that comes back.
    private struct Rule {
        let forward: String
        let backward: String
        let convention: InverseMutatorPair.Convention
    }

    private static let rules: [Rule] = [
        Rule(forward: "navigateto", backward: "navigateup", convention: .directionalVerb),
        Rule(forward: "push", backward: "pop", convention: .directionalVerb),
        Rule(forward: "open", backward: "close", convention: .directionalVerb),
        Rule(forward: "enter", backward: "exit", convention: .enterExit),
        Rule(forward: "descend", backward: "ascend", convention: .enterExit),
        Rule(forward: "select", backward: "deselect", convention: .enterExit),
        Rule(forward: "add", backward: "remove", convention: .enterExit)
    ]

    public static func candidates(in summaries: [FunctionSummary]) -> [InverseMutatorPair] {
        var byType: [String: [FunctionSummary]] = [:]
        for summary in summaries where isMutator(summary) {
            guard let type = summary.containingTypeName else { continue }
            byType[type, default: []].append(summary)
        }

        return byType.sorted { $0.key < $1.key }.flatMap { _, members -> [InverseMutatorPair] in
            rules.flatMap { pairs(in: members, under: $0) }
        }
    }

    /// Every pair one rule finds on one type — **every** pair, not the first.
    ///
    /// `members.first(where:)` on each side capped this at one pair per (type, rule), and
    /// `docs/measurements/normal-form-state-machine-writers.md` measured two types where that
    /// loses a law the tool had already found the halves of: `GRDB.Database` declares
    /// `add(function:)`/`remove(function:)` AND `add(collation:)`/`remove(collation:)` and yielded
    /// one row; `RuleDetailViewModel` declares three add/remove pairs (Disabled, OptIn, Only) and
    /// yielded one — the wrong one, since the first `add…` and the first `remove…` on that type
    /// name different rules.
    private static func pairs(
        in members: [FunctionSummary],
        under rule: Rule
    ) -> [InverseMutatorPair] {
        // The forward move must say WHICH way it went — see `isMove` — and must not announce a
        // second operation, which no single backward move undoes.
        let forwards = members.filter {
            matches($0.name, rule.forward) && isMove($0)
                && !InverseMutatorNoun.announcesASecondOperation($0, afterStem: rule.forward)
        }
        // The `forward.name != backward.name` guard the original carried is in the inner loop,
        // where the two are actually in hand.
        let backwards = members.filter { matches($0.name, rule.backward) }
        guard !forwards.isEmpty, !backwards.isEmpty else { return [] }

        var found: [InverseMutatorPair] = []
        for forward in forwards {
            let forwardNoun = InverseMutatorNoun.tokens(of: forward, afterStem: rule.forward)
            for backward in backwards where backward.name != forward.name {
                let backwardNoun = InverseMutatorNoun.tokens(of: backward, afterStem: rule.backward)
                // The backward move may name nothing — `navigateUp()`, and there is only one way
                // up — but only where there is one way DOWN too, since with two forwards nothing
                // says which one a single unnamed backward undoes. An empty FORWARD noun is never
                // excused: naming what moved is the forward's whole job, which is why
                // `add(_ anObject:)` × `removeObject(at:)` stays out.
                let namesTheSameThing = forwardNoun == backwardNoun
                    || (backwardNoun.isEmpty && forwards.count == 1)
                if namesTheSameThing {
                    found.append(
                        InverseMutatorPair(
                            forward: forward,
                            backward: backward,
                            convention: rule.convention
                        )
                    )
                }
            }
        }
        return found
    }

    /// The forward move must take an argument, and this gate is the difference between a law and a
    /// falsehood.
    ///
    /// Without it the rule pairs `selectAllFiles()` with `deselectAllFiles()` — and then proposes
    /// `deselectAll ∘ selectAll == id`, **which is not true**. `selectAll` sets the selection to
    /// everything and `deselectAll` clears it; compose them and you have the empty set, not the state
    /// you started in. A reader who wrote that test would watch it fail for a reason that is not a
    /// bug, and **a tool that proposes a false law is worse than one that proposes nothing** — it
    /// spends the reader's trust and gives nothing back.
    ///
    /// An inverse pair needs the forward to encode *which* move was made, so the backward has
    /// something specific to undo. `navigateToFolder(folder)` names the folder; `selectAllFiles()`
    /// names nothing, because it is not a move at all — it is an absolute setter, and two absolute
    /// setters never compose to the identity.
    ///
    /// The backward move is exempt: there is only one way up.
    static func isMove(_ summary: FunctionSummary) -> Bool {
        !summary.parameters.isEmpty
    }

    /// A move: returns nothing, and belongs to a type. `async` is allowed — a navigation that reloads
    /// from the network is still a navigation, and the *state* law holds regardless of what it awaits.
    static func isMutator(_ summary: FunctionSummary) -> Bool {
        (summary.returnTypeText == nil || summary.returnTypeText == "Void")
            && summary.containingTypeName != nil
            && !summary.isStatic
    }

    /// Prefix match, case-insensitive: `navigateToFolder` matches `navigateto`.
    private static func matches(_ name: String, _ stem: String) -> Bool {
        name.lowercased().hasPrefix(stem)
    }
}
