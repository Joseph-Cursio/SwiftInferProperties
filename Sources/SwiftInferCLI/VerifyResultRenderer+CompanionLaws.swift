import SwiftInferCore

/// #711 — the companion laws a verify run checked, rendered under the primary law's verdict and
/// never as it (`CompanionLawOutcome`).
extension VerifyResultRenderer {

    /// One indented line per companion law that ran, plus what a binding refutation means. `""`
    /// when none ran, so every entry without companions renders byte for byte as before.
    static func renderCompanions(_ companions: [CompanionLawOutcome]) -> String {
        guard !companions.isEmpty else { return "" }
        var lines = companions.map { "\n    companion law: \($0.rendered)" }
        if companions.refutation != nil {
            lines.append(
                "\n    → not Verified: the accepted stub checks this law too, so it would fail. "
                    + "The primary law's verdict stands, and nothing is vetoed."
            )
        }
        return lines.joined()
    }
}
