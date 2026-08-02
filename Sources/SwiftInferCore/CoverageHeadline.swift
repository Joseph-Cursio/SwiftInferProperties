import Foundation

/// **The line that must accompany every `discover` result.**
///
/// A `discover` count read on its own is close to meaningless, and the reason is a thought
/// experiment the repo owner posed: *if PropertyLawKit were perfect at finding testable
/// properties, there would be nothing left to discover.* A tool reporting `22 suggestions`
/// would then be reporting total success in the exact typography of total failure. The
/// leaderboard fixture's scorecards were withdrawn for precisely this — they scored
/// `discover` as if the kit did not exist.
///
/// So the kit's contribution ships **beside** the count, in the same unit, always.
///
/// ## Why stdout, not the diagnostic channel
///
/// `ProtocolCoverageAudit.diagnostics` already said something like this, on stderr, as a
/// `note:`. It was invisible in practice: the 2026-08-01 census swept eight corpora with
/// `2>/dev/null` on every invocation and never surfaced the line once — including the runs
/// whose numbers were then written into the findings doc. A channel that the tool's own
/// author redirects away is not a channel. This goes where the suggestion count goes.
///
/// ## Laws, not carriers
///
/// The count is **laws**, because carriers are not comparable to suggestions and reporting
/// them side by side invites exactly the unit confusion that `ProtocolCoverageAudit`'s first
/// version shipped — *"150 carrier(s) had laws suppressed"* on a target where the measured
/// suppression was zero. `discover: 22` against `kit: 297` is that mistake again with the
/// numbers in different columns.
/// What the kit covers on this corpus, reduced to the three numbers the headline needs.
///
/// Carried on `PipelineResult` so the renderer does not have to re-derive it — and so the
/// line cannot be forgotten by a code path that renders suggestions without asking.
public struct CoverageSummary: Sendable, Equatable {
    public let lawCount: Int
    public let carrierCount: Int
    public let evidenceState: CoverageHeadline.EvidenceState

    public init(lawCount: Int, carrierCount: Int, evidenceState: CoverageHeadline.EvidenceState) {
        self.lawCount = lawCount
        self.carrierCount = carrierCount
        self.evidenceState = evidenceState
    }

    /// Reduce the per-carrier audit to the headline's three numbers.
    public static func summarize(_ findings: [ProtocolCoverageAudit.Finding]) -> Self {
        let contradicted = findings.filter { $0.standing == .contradicted }.count
        let state: CoverageHeadline.EvidenceState
        if contradicted > 0 {
            state = .ranButMissed(carriers: contradicted)
        } else if findings.contains(where: { $0.standing == .verified }) {
            state = .ran
        } else {
            state = .noEvidence
        }
        return Self(
            lawCount: ProtocolCoverageAudit.lawTotal(for: findings),
            carrierCount: findings.count,
            evidenceState: state
        )
    }
}

public enum CoverageHeadline {

    /// One line pairing what `discover` proposes with what the kit's suites cover.
    ///
    /// `carriers == 0` still renders. A project with no covered conformances is a real and
    /// informative state — it means the suggestion count *is* the whole picture — and
    /// suppressing the line there would reintroduce the silence this exists to remove.
    public static func line(
        suggestionCount: Int,
        lawCount: Int,
        carrierCount: Int,
        evidenceState: EvidenceState
    ) -> String {
        let laws = "\(lawCount) law\(lawCount == 1 ? "" : "s")"
        let carriers = "\(carrierCount) carrier\(carrierCount == 1 ? "" : "s")"
        return "Coverage: discover proposes \(suggestionCount); PropertyLawKit's suites cover "
            + "\(laws) over \(carriers) — \(evidenceState.clause)"
    }

    /// What the kit evidence says, in the three states `ProtocolCoverageAudit` distinguishes.
    public enum EvidenceState: Sendable, Equatable {
        /// Kit evidence exists and names these carriers.
        case ran
        /// No kit evidence at all — the normal state, and not by itself a defect.
        case noEvidence
        /// Evidence exists and omits some carriers: the kit demonstrably ran elsewhere and
        /// demonstrably not here, so those laws are checked by nothing.
        case ranButMissed(carriers: Int)

        var clause: String {
            switch self {
            case .ran:
                return "kit evidence confirms they ran."

            case .noEvidence:
                return "no kit evidence, so it is unknown whether they ran. Every one has an "
                    + "explicit suite you can run; call "
                    + "`KitEvidenceRecorder.record(results, for:packageRoot:)` "
                    + "(import SwiftInferKitEvidence) after it to turn this into a check."

            case .ranButMissed(let carriers):
                return "kit evidence exists but omits \(carriers) of them, so those laws are "
                    + "currently checked by nothing."
            }
        }
    }
}
