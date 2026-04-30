/// Visibility tier a `Score` falls into per PRD v0.3 §4.2.
///
/// Thresholds are tunable starting points — §17's calibration loop is what
/// fixes them empirically once SwiftInfer has run against open-source
/// corpora. Treat the numbers below as v0.3 defaults, not load-bearing
/// constants.
public enum Tier: String, Sendable, Equatable, CaseIterable {

    /// Score >= 75. Shown by default.
    case strong

    /// 40 <= Score < 75. Shown by default.
    case likely

    /// 20 <= Score < 40. Hidden by default; surfaced with `--include-possible`.
    case possible

    /// Score < 20 or any veto fired. Never shown.
    case suppressed

    /// Tier mapping per PRD v0.3 §4.2.
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

    /// Human-facing label rendered in the explainability block header.
    public var label: String {
        switch self {
        case .strong: return "Strong"
        case .likely: return "Likely"
        case .possible: return "Possible"
        case .suppressed: return "Suppressed"
        }
    }

    /// `false` for `.possible` and `.suppressed`; CLI hides those by default
    /// (the latter unconditionally per §4.2).
    public var isVisibleByDefault: Bool {
        switch self {
        case .strong, .likely: return true
        case .possible, .suppressed: return false
        }
    }
}
