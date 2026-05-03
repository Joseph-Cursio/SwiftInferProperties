import SwiftInferCore

/// Per-op signal record (M8.4.b.2). Tracks whether a specific binary op
/// on the type has the Monoid signal set (assoc + identity-element).
/// Ring detection scans `perOp` for one additive-named + one
/// multiplicative-named op both Monoid-shaped; if both exist, the
/// type's claim is Ring rather than the type-level CommutativeMonoid /
/// Group / etc.
struct OpInfo {
    var hasAssociativity: Bool = false
    var hasIdentity: Bool = false
    var identityName: String?
}

/// Per-type accumulator — collects which structural signals fired on
/// the type and which suggestions contributed. The `proposals`
/// computed property (in `RefactorBridgeAccumulator+Promotions.swift`)
/// promotes the accumulator to one or more `RefactorBridgeProposal`s
/// when the signal set warrants them.
///
/// Tracks the witness names per-arm: the associativity arm contributes
/// `combineWitness` (function name from evidence[0]), the
/// identity-element arm contributes `identityWitness` (constant name
/// from evidence[1] — see `IdentityElementTemplate`'s
/// `makeEvidence(identity:)` for the two-row evidence shape), and
/// M8.3's inverse-element pairing pass contributes `inverseWitness`
/// (function name from `InverseElementPair.inverse.name`).
struct RefactorBridgeAccumulator {
    let typeName: String
    var hasAssociativity: Bool = false
    var hasIdentityElement: Bool = false
    var hasCommutativity: Bool = false
    var hasIdempotence: Bool = false
    var hasInverseElement: Bool = false
    var combineWitness: String?
    var identityWitness: String?
    var inverseWitness: String?
    var perOp: [String: OpInfo] = [:]
    var contributing: [Suggestion] = []
    var identities: Set<SuggestionIdentity> = []

    mutating func record(signal: TemplateSignal, from suggestion: Suggestion) {
        let opName = WitnessExtractor.combineWitnessName(from: suggestion)
        switch signal {
        case .associativity:
            recordAssociativity(opName: opName)
        case .identityElement:
            recordIdentityElement(opName: opName, suggestion: suggestion)
        case .commutativity:
            recordCommutativity(opName: opName)
        case .idempotence:
            recordIdempotence(opName: opName)
        }
        contributing.append(suggestion)
        identities.insert(suggestion.identity)
    }

    /// M8.3 inverse-element witness — recorded from
    /// `InverseElementPairing` output, not a Suggestion. Doesn't add
    /// to `relatedIdentities` since no suggestion contributed (the
    /// user doesn't see an "inverse-element" suggestion in `discover`);
    /// the Group prompt threading uses the associativity /
    /// identity-element identities that DO carry.
    mutating func recordInverseElement(witness: String) {
        hasInverseElement = true
        if inverseWitness == nil {
            inverseWitness = witness
        }
    }

    private mutating func recordAssociativity(opName: String?) {
        hasAssociativity = true
        if combineWitness == nil {
            combineWitness = opName
        }
        if let opName {
            perOp[opName, default: OpInfo()].hasAssociativity = true
        }
    }

    private mutating func recordIdentityElement(opName: String?, suggestion: Suggestion) {
        hasIdentityElement = true
        if combineWitness == nil {
            combineWitness = opName
        }
        let identity = WitnessExtractor.identityWitnessName(from: suggestion)
        if identityWitness == nil {
            identityWitness = identity
        }
        if let opName {
            perOp[opName, default: OpInfo()].hasIdentity = true
            if perOp[opName]?.identityName == nil {
                perOp[opName]?.identityName = identity
            }
        }
    }

    private mutating func recordCommutativity(opName: String?) {
        hasCommutativity = true
        if combineWitness == nil {
            combineWitness = opName
        }
    }

    /// Idempotence on a binary op `(T, T) -> T` is the Semilattice
    /// idempotence law `combine(a, a) == a`. Note: M2's `idempotence`
    /// template fires on unary `T -> T` shapes (`f(f(x)) == f(x)`);
    /// only binary-op matches contribute here.
    private mutating func recordIdempotence(opName: String?) {
        hasIdempotence = true
        if combineWitness == nil {
            combineWitness = opName
        }
    }
}

/// Structural-conformance signals the orchestrator recognizes. M7.5
/// shipped associativity + identityElement; M8.4.a adds commutativity +
/// idempotence (driving CommutativeMonoid / Semilattice) and
/// inverseElement (driving Group). M8.4.b.2 adds Ring detection via
/// the per-op tracking on the accumulator (no new signal — Ring is a
/// pattern over per-op Monoid claims).
///
/// Note: `inverseElement` doesn't have a corresponding template — it's
/// a witness record from M8.3's `InverseElementPairing`. The
/// orchestrator threads it through `recordInverseElement(witness:)`
/// rather than the suggestion-driven `record(signal:from:)` path.
enum TemplateSignal {
    case associativity
    case identityElement
    case commutativity
    case idempotence
}
