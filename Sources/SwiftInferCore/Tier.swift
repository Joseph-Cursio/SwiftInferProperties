/// Visibility tier a `Score` falls into per PRD v0.3 §4.2.
///
/// Thresholds are tunable starting points — §17's calibration loop is what
/// fixes them empirically once SwiftInfer has run against open-source
/// corpora. Treat the numbers below as v0.3 defaults, not load-bearing
/// constants.
public enum Tier: String, Sendable, Equatable, CaseIterable, Codable {

    /// V1.65 — top tier: a `.strong` suggestion whose `swift-infer verify`
    /// run reached `.measuredBothPass` (human-signal-strong *and*
    /// machine-confirmed). Never returned by `Tier(score:)` — score alone
    /// can't know the verify outcome; set by the discover render path via
    /// `promoted(byVerifyOutcome:)`, mirroring how `.advisory` is set
    /// explicitly by the surfacing pipeline. Declared first so
    /// `Tier.allCases` reads verified → strong → likely → … . Shown by
    /// default. V1.68 — `.verified` reaches `DecisionRecord.tier` too:
    /// `--interactive` triage records the *effective* tier so the
    /// `metrics` tier-mix reflects verified picks. `Baseline.tier` still
    /// keeps the base score-derived tier (a snapshot is a pre-verify
    /// surface marker, not a decision).
    case verified

    /// Score >= 75. Shown by default.
    case strong

    /// 40 <= Score < 75. Shown by default.
    case likely

    /// 20 <= Score < 40. Hidden by default; surfaced with `--include-possible`.
    case possible

    /// Score < 20 or any veto fired. Never shown.
    case suppressed

    /// TestLifter M11.0 — informational tier for stand-alone advisory
    /// findings that don't carry a runnable property (today: equivalence-
    /// class detection per §7.8 third example). Never returned by
    /// `Tier(score:)` — set explicitly by the surfacing pipeline. Shown by
    /// default so users see the documentation surface in the discover
    /// stream; CLI rendering distinguishes `[Advisory]` from
    /// `[Strong]`/`[Likely]`/`[Possible]` so consumers don't conflate it
    /// with a runnable suggestion.
    case advisory

    /// Tier mapping per PRD v0.3 §4.2. Never produces `.verified` or
    /// `.advisory` — both are set explicitly by the surfacing pipeline
    /// (verify evidence / equivalence-class detection), not derived from
    /// score alone.
    public init(score: Int) {
        switch score {
        case 75...:
            self = .strong
        case 40..<75:
            self = .likely
        case 20..<40:
            self = .possible
        default:
            self = .suppressed
        }
    }

    /// V1.65 — resolve the effective discover-presentation tier given a
    /// suggestion's persisted verify outcome. A `.strong` suggestion
    /// whose verify run reached `.measuredBothPass` is promoted to
    /// `.verified`; every other `(tier, outcome)` pair — including a
    /// `nil` outcome (no verify evidence) — returns `self` unchanged.
    public func promoted(byVerifyOutcome outcome: VerifyEvidenceOutcome?) -> Self {
        guard self == .strong, outcome == .measuredBothPass else { return self }
        return .verified
    }

    /// Human-facing label rendered in the explainability block header.
    public var label: String {
        switch self {
        case .verified: return "Verified"
        case .strong: return "Strong"
        case .likely: return "Likely"
        case .possible: return "Possible"
        case .suppressed: return "Suppressed"
        case .advisory: return "Advisory"
        }
    }

    /// `false` for `.possible` and `.suppressed`; CLI hides those by default
    /// (the latter unconditionally per §4.2). `.advisory` is shown by
    /// default — the equivalence-class documentation surface needs to
    /// reach users without an opt-in flag.
    public var isVisibleByDefault: Bool {
        switch self {
        case .verified, .strong, .likely, .advisory: return true
        case .possible, .suppressed: return false
        }
    }
}
