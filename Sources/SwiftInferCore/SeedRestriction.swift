import Foundation

/// **What would have to move** for a test to reach a seeded symbol, as the linter determined it.
///
/// `SeedKind.restrictedFunction` says a test cannot call the symbol. This says *why*, and the two
/// answers are not interchangeable remedies: widening a member nested inside a `private` type
/// compiles and changes nothing. A consumer acting on the kind alone can emit a patch that unblocks
/// nothing, then read the resulting verification failure as evidence against the **law**.
///
/// ## Why this repo needs it, when it computes the same thing itself
///
/// `FunctionScanner.accessRestriction` answers the same question locally, and for a directly nested
/// declaration it is the better source — it reads the syntax. But it is **same-declaration only**:
/// a member of an unmarked `extension PrivateType { … }` is not caught, because resolving that
/// needs the type's own declaration, which may be visited later or live in another file. The linter
/// resolves it. So the field is not a duplicate of local knowledge; it is the part of the answer
/// this side structurally cannot compute in one pass.
///
/// That is the same argument the `effect` tier is carried on, and the same one the whole seam runs
/// on: the producer pays for a cross-file analysis once, and the consumer gets it for free rather
/// than approximating it inside a per-run budget.
///
/// ## It arrived on 2026-08-03 and was dropped on the floor until 2026-08-06
///
/// `Codable` ignores unknown keys, so a producer adding a field is invisible on this side — the
/// exact mirror of the silent `kind` default the v1 → v2 bump existed to delete, and silent in the
/// same direction. Three days of manifests carried the answer to a question this repo was getting
/// wrong (`AccessRestriction.enclosingTypeNotVisibleToTests`, fixed the same day). `SeedFieldParity`
/// exists so the next added field fails a test instead of passing unnoticed.
public enum SeedRestriction: Sendable, Equatable, Hashable {

    /// The declaration's own access modifier is the blocker. Widening it works.
    case declaration

    /// An enclosing type is the blocker. **Widening the declaration alone is a no-op.**
    ///
    /// The producer returns this whenever both apply, *"because it names the binding constraint"* —
    /// the one still blocking after the other is fixed. This repo's local classifier orders its
    /// checks to reach the same answer, deliberately and for the same stated reason.
    case enclosingType

    /// A spelling a newer producer emits and this build does not know.
    ///
    /// Same asymmetry as `SeedKind.unrecognised` and `SeedRole.unrecognised`, resolved the same way:
    /// never guess a remedy from an unknown restriction. Guessing `declaration` would propose the
    /// widening patch this type exists to prevent; treating it as unknown loses a hint and says so.
    case unrecognised(String)

    public var rawValue: String {
        switch self {
        case .declaration:
            return "declaration"

        case .enclosingType:
            return "enclosing-type"

        case .unrecognised(let raw):
            return raw
        }
    }
}

extension SeedRestriction: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "declaration":
            self = .declaration

        case "enclosing-type":
            self = .enclosingType

        default:
            self = .unrecognised(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension AccessRestriction {

    /// This scan's answer, corrected by the manifest's where the manifest can see further.
    ///
    /// **Only one direction of disagreement is resolved, and the asymmetry is the point.** The
    /// manifest wins exactly when it reports `enclosing-type` and this scan reported
    /// `.notVisibleToTests`, because that is the one combination with a known structural cause: the
    /// enclosing-type stack is same-declaration only, so a member of an unmarked `extension` of a
    /// `private` type reads here as blocked by its own modifier. Believing the manifest there turns
    /// a widening patch that cannot work into the remedy that can.
    ///
    /// Every other disagreement is left alone rather than arbitrated. Preferring the manifest
    /// wholesale would mean a stale or mis-pathed seed could silently overrule a syntactic reading
    /// of the declaration in front of us — and the failure would be invisible, because both answers
    /// are plausible sentences about access. `disagrees(with:)` reports those instead; see
    /// `Discover+GenericLaws`, which surfaces them as one aggregate line.
    public func reconciled(with seed: SeedRestriction?) -> AccessRestriction {
        guard seed == .enclosingType, self == .notVisibleToTests else { return self }
        return .enclosingTypeNotVisibleToTests
    }

    /// True when this scan and the manifest name **different binding constraints** for the same
    /// symbol, after reconciliation.
    ///
    /// Reported, never silently resolved. The two tools disagreeing without saying so is precisely
    /// how `restricted-function` went wrong the first time: 316 of 468 supposedly analysable seeds
    /// named a function no test could call, and *"the two tools had been disagreeing silently, and
    /// only noticed once both sides stated their beliefs in a comparable vocabulary."* This is that
    /// vocabulary, so the check costs nothing but the sentence.
    ///
    /// A `nil` seed restriction is not a disagreement — the producer classifies only
    /// `restricted-function` seeds, so absence is "not asked", the same reading `role` and `effect`
    /// get. An `unrecognised` spelling is not one either: this build cannot say what it means, and
    /// inventing a conflict out of a word it does not know would report a version skew as a defect
    /// in the code.
    public func disagrees(with seed: SeedRestriction?) -> Bool {
        switch seed {
        case .declaration:
            return self == .enclosingTypeNotVisibleToTests

        case .enclosingType:
            return self != .enclosingTypeNotVisibleToTests && self != .notVisibleToTests

        case .unrecognised, .none:
            return false
        }
    }
}
