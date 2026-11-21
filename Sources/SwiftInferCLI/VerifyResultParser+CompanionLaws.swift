import SwiftInferCore

/// #711 — reading the companion laws a stub ran beside its primary law
/// (`StrategistDispatchEmitter.dedupeCompanionLaws`, `CompanionLawOutcome`).
///
/// **Read apart from `parse`, and apart from the exit code.** `parse` decides the primary law's
/// verdict from `VERIFY_DEFAULT_RESULT` / `VERIFY_EDGE_RESULT` and the exit code, and nothing here
/// can change it: a companion never prints those markers and never exits. Per law and per pass:
///
/// - no `_BEGIN`: the law did not run (the primary law failed first, or the entry has none), and
///   nothing is reported;
/// - `_BEGIN` and `_RESULT: PASS` / `FAIL`: held or failed, with the failing trial, input and output;
/// - `_BEGIN` and no `_RESULT`: the process trapped inside the law. Reported as `trapped`, and
///   `verdictSurvivingTrappedCompanion` keeps the primary law's `.bothPass`: the companions run
///   after both of its passes, so its verdict was already complete.
extension VerifyResultParser {

    /// The laws a stub may run as companions, in the order it runs them.
    static let companionLawNames = ["C1", "C2"]

    static func companionLaws(_ output: VerifierSubprocess.Output) -> [CompanionLawOutcome] {
        let lines = output.stdout.split(separator: "\n").map(String.init)
        return companionLawNames.compactMap { law in
            companionLaw(law, prefix: "VERIFY_DEFAULT_LAW_\(law)_", in: lines)
        }
    }

    /// Both of the primary law's passes printed PASS, then the run trapped inside a companion.
    /// The companions run last, so the primary law's verdict is complete: it is `.bothPass`, and
    /// `companionLaws` reports the trapped law. Without this rule `parse` reads PASS + PASS + a
    /// signal as `.error`, and a companion would replace a verdict the run actually produced.
    static func verdictSurvivingTrappedCompanion(
        _ output: VerifierSubprocess.Output, lines: [String]
    ) -> VerifyOutcome? {
        guard lines.contains(where: { $0.hasPrefix("VERIFY_DEFAULT_RESULT: PASS") }),
              lines.contains(where: { $0.hasPrefix("VERIFY_EDGE_RESULT: PASS") }),
              trapReason(from: output) != nil,
              companionLaws(output).contains(where: { $0.status == .trapped }) else {
            return nil
        }
        return .bothPass(
            defaultTrials: Int(value(forMarker: "VERIFY_DEFAULT_TRIALS:", in: lines) ?? "") ?? 0,
            edgeTrials: Int(value(forMarker: "VERIFY_EDGE_TRIALS:", in: lines) ?? "") ?? 0,
            edgeSampled: Int(value(forMarker: "VERIFY_EDGE_SAMPLED:", in: lines) ?? "") ?? 0
        )
    }

    /// `companionLaws` as a record stores it: `nil` when none ran, so a record without
    /// companions encodes as it did before the field existed.
    static func recordedCompanionLaws(_ output: VerifierSubprocess.Output) -> [CompanionLawOutcome]? {
        let laws = companionLaws(output)
        return laws.isEmpty ? nil : laws
    }

    private static func companionLaw(_ law: String, prefix: String, in lines: [String]) -> CompanionLawOutcome? {
        guard lines.contains(prefix + "BEGIN") else { return nil }
        switch value(forMarker: prefix + "RESULT:", in: lines) {
        case "PASS":
            return CompanionLawOutcome(law: law, status: .held)

        case "FAIL":
            return CompanionLawOutcome(
                law: law,
                status: .failed,
                trial: value(forMarker: prefix + "TRIAL:", in: lines).flatMap { Int($0) },
                input: value(forMarker: prefix + "INPUT:", in: lines),
                output: value(forMarker: prefix + "OUTPUT:", in: lines)
            )

        default:
            return CompanionLawOutcome(law: law, status: .trapped)
        }
    }
}
