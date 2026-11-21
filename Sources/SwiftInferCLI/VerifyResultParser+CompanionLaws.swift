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
/// - `_BEGIN` and no `_RESULT`: the process trapped inside the law. Reported as `trapped`, because
///   `parse` reads a trap after `VERIFY_DEFAULT_RESULT: PASS` as a survived edge pass, and the
///   companion would otherwise vanish behind a `bothPass`.
extension VerifyResultParser {

    /// The laws a stub may run as companions, in the order it runs them.
    static let companionLawNames = ["C1", "C2"]

    static func companionLaws(_ output: VerifierSubprocess.Output) -> [CompanionLawOutcome] {
        let lines = output.stdout.split(separator: "\n").map(String.init)
        return [(CompanionLawOutcome.Pass.default, "DEFAULT"), (.edge, "EDGE")].flatMap { pass, label in
            companionLawNames.compactMap { law in
                companionLaw(law, pass: pass, prefix: "VERIFY_\(label)_LAW_\(law)_", in: lines)
            }
        }
    }

    /// `companionLaws` as a record stores it: `nil` when none ran, so a record without
    /// companions encodes as it did before the field existed.
    static func recordedCompanionLaws(_ output: VerifierSubprocess.Output) -> [CompanionLawOutcome]? {
        let laws = companionLaws(output)
        return laws.isEmpty ? nil : laws
    }

    private static func companionLaw(
        _ law: String, pass: CompanionLawOutcome.Pass, prefix: String, in lines: [String]
    ) -> CompanionLawOutcome? {
        guard lines.contains(prefix + "BEGIN") else { return nil }
        switch value(forMarker: prefix + "RESULT:", in: lines) {
        case "PASS":
            return CompanionLawOutcome(law: law, pass: pass, status: .held)

        case "FAIL":
            return CompanionLawOutcome(
                law: law,
                pass: pass,
                status: .failed,
                trial: value(forMarker: prefix + "TRIAL:", in: lines).flatMap { Int($0) },
                input: value(forMarker: prefix + "INPUT:", in: lines),
                output: value(forMarker: prefix + "OUTPUT:", in: lines)
            )

        default:
            return CompanionLawOutcome(law: law, pass: pass, status: .trapped)
        }
    }
}
