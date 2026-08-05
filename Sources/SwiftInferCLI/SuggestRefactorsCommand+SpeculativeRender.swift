import Foundation
import SwiftInferCore

/// Rendering for `suggest-refactors --speculative`, split out at the type-body
/// cap. The seam is real: this file decides what a reader is *shown*, and the
/// decision it encodes — report the non-recommendations rather than hide them —
/// is the one most likely to be quietly reversed for a tidier demo.
extension SwiftInferCommand.SuggestRefactors {

    /// Renders proposals **recommended first**, and reports the rest rather
    /// than hiding them.
    ///
    /// A run where nothing held is a real answer about this codebase — measured
    /// 2026-08-04, 14 of 20 widenings gained no law at all — and suppressing the
    /// non-recommendations would make the command look more effective than it
    /// is, which is the failure mode `prove-then-show` exists to avoid.
static func renderSpeculative(_ proposals: [SpeculativeProposal]) -> String {
        guard !proposals.isEmpty else {
            return "No widenable candidates. Only `private`/`fileprivate` declarations "
                + "qualify — widening a nested local or an explicit `internal` unblocks "
                + "nothing.\n"
        }
        let recommended = proposals.filter(\.verdict.recommendsRefactor)
        var out = "Speculative refactors — \(recommended.count) of \(proposals.count) "
            + "recommended\n\n"
        for proposal in recommended {
            out += """
            RECOMMENDED  \(proposal.path)
              law:    \(proposal.lawDescription)
              why:    \(proposal.detail ?? "")
              source: \(proposal.sourceDigest)

            \(proposal.diff)


            """
        }
        let rest = proposals.filter { !$0.verdict.recommendsRefactor }
        if !rest.isEmpty {
            out += "Not recommended:\n"
            for proposal in rest {
                out += "  \(proposal.verdict.rawValue)  \(proposal.path) — "
                    + "\(proposal.lawDescription)\n"
            }
        }
        return out
    }
}
