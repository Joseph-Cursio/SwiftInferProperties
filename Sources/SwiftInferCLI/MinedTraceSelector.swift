import Foundation
import SwiftInferCore
import SwiftInferTestLifter
import SwiftParser
import SwiftSyntax

/// TestStore Trace Mining — turns raw mined `MinedActionTrace`s into the
/// verifier-replayable `SeedTrace`s for a reducer candidate. Slice 3 widens
/// Slice 2's payload-free-`.tca`-only selection:
///
///   - **3a — any carrier.** Selection is driven by the `alphabet`
///     (`ActionAlphabetScanner`), which resolves the Action enum's cases +
///     labels for `.tca`, `.elmStyle`, or `.generic`, so the `.tca`-only gate
///     is gone. (In practice `TestStore` is a TCA construct, but the alphabet
///     is what makes the mechanism carrier-agnostic and label-correct.)
///   - **3b — payload generalization.** A payload-bearing mined action
///     (`.select(a.id)` — its arg references a test-body local the verifier
///     can't see) is generalized to `.select(<generated>)` when every
///     parameter type is cheaply defaultable, reusing the same canned literals
///     the random `.tca` generator already explores (so no new precision risk).
///     A non-defaultable parameter drops the trace.
///   - **3c — initial-state mining.** A self-contained `TestStore(initialState:)`
///     expression (no test-body-local references) becomes the trace's starting
///     State; a fixture-referencing one falls back to the reducer default.
///   - **3e — Markov synthesis.** With `includeMarkov`, extra orderings are
///     synthesized from a first-order model of the mined transitions (novel
///     recombinations of observed steps), appended as more seed traces.
///
/// Invariants preserved from Slice 2: reducer join, stale-case guard, non-empty.
enum MinedTraceSelector {

    static func select(
        from traces: [MinedActionTrace],
        candidate: ReducerCandidate,
        alphabet: [ActionCaseSpec],
        includeMarkov: Bool = false
    ) -> [ActionSequenceStubEmitter.SeedTrace] {
        guard !alphabet.isEmpty else { return [] }
        let specs = Dictionary(alphabet.map { ($0.name, $0) }) { first, _ in first }
        let joined = traces.filter { joins($0, candidate: candidate) }
        let selected = joined.compactMap { seedTrace(for: $0, specs: specs) }
        guard includeMarkov else { return selected }
        return selected + markovSynthesized(from: selected)
    }

    // MARK: - Join

    private static func joins(_ trace: MinedActionTrace, candidate: ReducerCandidate) -> Bool {
        // A reducer method/struct joins by enclosing type; a nil-reducer
        // (bare-`store` fallback) trace can't be attributed and is dropped.
        guard let enclosing = candidate.enclosingTypeName else { return false }
        return trace.reducerTypeName == enclosing
    }

    // MARK: - Per-trace selection

    private static func seedTrace(
        for trace: MinedActionTrace,
        specs: [String: ActionCaseSpec]
    ) -> ActionSequenceStubEmitter.SeedTrace? {
        guard !trace.sent.isEmpty else { return nil }
        var actions: [String] = []
        for mined in trace.sent {
            // A stale case (not in the alphabet) or a non-defaultable payload
            // drops the whole trace.
            guard let expr = specs[mined.caseName]?.constructibleExpression() else {
                return nil
            }
            actions.append(expr)
        }
        let initialState = selfContainedInitialState(trace.initialStateExpr)
        return ActionSequenceStubEmitter.SeedTrace(initialState: initialState, actions: actions)
    }

    // MARK: - 3c: self-contained initial state

    /// Returns the mined `TestStore(initialState:)` expression when it is
    /// verifier-constructible — i.e. references no test-body-local binding.
    /// Heuristic: any lowercase-leading identifier reference (`a`, `items`,
    /// `fixture`) marks a local, and so does a lowercase member reached through
    /// a base (`Feature.State.initial`, `FeatureTests.fixture`), because the
    /// verifier cannot tell a production static from one the test target
    /// declares; `Self` and a `$` projection mark one too. Type/enum references
    /// (`Feature`, `.red`), key paths (`\.name`) and literals are fine.
    /// Conservative — a false "not self-contained" only costs a mined starting
    /// state (falls back to the reducer default), while a false
    /// "self-contained" is pasted into the verifier stub, fails its build, and
    /// costs every verdict for the reducer.
    static func selfContainedInitialState(_ expr: String?) -> String? {
        guard let expr, !expr.isEmpty else { return nil }
        let tree = Parser.parse(source: expr)
        let collector = LowercaseReferenceCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.sawLowercaseReference ? nil : expr
    }

    // MARK: - 3e: Markov synthesis

    /// Synthesize novel orderings from a first-order Markov model of the mined
    /// transitions. Deterministic (no RNG — byte-stable emit): for each distinct
    /// starting action, greedily follow first-observed successors until a cycle
    /// or a length cap, recombining steps that appeared in *different* traces
    /// (e.g. `[A,B]` + `[B,C]` → `[A,B,C]`). Only emits a synthesized trace when
    /// it differs from every input trace. Uses the reducer default initial state.
    static func markovSynthesized(
        from traces: [ActionSequenceStubEmitter.SeedTrace]
    ) -> [ActionSequenceStubEmitter.SeedTrace] {
        let sequences = traces.map(\.actions)
        var successors: [String: [String]] = [:]
        for sequence in sequences {
            for (index, action) in sequence.enumerated() where index + 1 < sequence.count {
                successors[action, default: []].append(sequence[index + 1])
            }
        }
        let starts = Array(Set(sequences.compactMap(\.first))).sorted()
        let existing = Set(sequences)
        let lengthCap = 16
        var synthesized: [[String]] = []
        for start in starts {
            var walk = [start]
            var seen: Set<String> = [start]
            while walk.count < lengthCap, let next = successors[walk[walk.count - 1]]?.first(
                where: { !seen.contains($0) }
            ) {
                walk.append(next)
                seen.insert(next)
            }
            if walk.count > 1, !existing.contains(walk), !synthesized.contains(walk) {
                synthesized.append(walk)
            }
        }
        return synthesized.map { ActionSequenceStubEmitter.SeedTrace(initialState: nil, actions: $0) }
    }
}

/// Detects any lowercase-leading identifier reference in a parsed expression —
/// the marker of a test-body-local binding in a mined `initialState:` expr.
///
/// ⚠ Two names are not references: a key-path component's (`\.name`), a member
/// of the key path's root type, and a leading-dot member's (`.red`), a member of
/// the type the context supplies. Counting them dropped `Feature.State(sort:
/// \.name)` and `Feature.State(color: .red)`. A member reached through a base
/// still counts when lowercase: `FeatureTests.fixture` and `Self.items` name
/// statics only the test target declares, and the stub that receives the
/// expression compiles production sources alone. `Self` is the test suite here
/// and the stub there; a `$`-projection reads a test-local's wrapper. The base
/// of a member access, and a key-path subscript's argument, are still visited.
private final class LowercaseReferenceCollector: SyntaxVisitor {
    private(set) var sawLowercaseReference = false

    override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
        if node.baseName.tokenKind == .keyword(.Self) {
            sawLowercaseReference = true
            return .skipChildren
        }
        if node.baseName.text.hasPrefix("$") {
            // `$0` is a closure's own parameter; `$store` projects a test-local's wrapper.
            if case .dollarIdentifier = node.baseName.tokenKind { return .skipChildren }
            sawLowercaseReference = true
            return .skipChildren
        }
        if node.isKeyPathComponentName || node.isImplicitMemberName { return .skipChildren }
        if let first = node.baseName.text.first, first.isLowercase {
            sawLowercaseReference = true
        }
        return .visitChildren
    }
}
