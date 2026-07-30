/// One contributing signal collected by a template against a candidate.
///
/// Signals are independent per PRD §4.1 — a suggestion can earn or
/// lose confidence from naming alone, types alone, or any combination.
/// The `weight` is signed; vetoes use `Signal.vetoWeight` rather than a
/// large negative number, and `Score` collapses any vetoed signal to the
/// `.suppressed` tier regardless of total.
public struct Signal: Sendable, Equatable {

    // The `Kind` catalogue lives in `Signal+Kind.swift` — it is a documented
    // vocabulary large enough to have pushed this file past the 400-line cap on its
    // own, and every case there carries the measurement that justifies its weight.

    /// Sentinel weight that marks a veto. Score arithmetic never sums this
    /// — `Score` checks `isVeto` per signal and short-circuits.
    public static let vetoWeight = Int.min

    public let kind: Kind
    public let weight: Int
    public let detail: String

    public init(kind: Kind, weight: Int, detail: String) {
        self.kind = kind
        self.weight = weight
        self.detail = detail
    }

    /// `true` if this signal vetoes the entire suggestion (PRD §4.4).
    public var isVeto: Bool {
        weight == Self.vetoWeight
    }

    /// Bullet text the explainability block (PRD §4.5) renders for this
    /// signal. Vetoes render as `"<detail> (veto)"`; non-vetoed signals
    /// render `"<detail> (<sign><weight>)"` with `+`/`-` prefixed to the
    /// weight. Templates compose this into their `whySuggested` lines at
    /// suggest time so the renderer just lays out bullets.
    ///
    /// M4.4 consolidated five copies of this formatter (one per
    /// shipped template) into a single value-type extension per the M4
    /// plan's open decision #4 default `(b)` — keeps `whySuggested:
    /// [String]` shape unchanged while eliminating drift risk between
    /// templates.
    public var formattedLine: String {
        if isVeto {
            return "\(detail) (veto)"
        }
        let sign = weight >= 0 ? "+" : ""
        return "\(detail) (\(sign)\(weight))"
    }
}
