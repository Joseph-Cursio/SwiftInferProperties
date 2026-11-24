/// #711 — the outcome of a **companion law**: a law the accepted stub also checks, run by verify
/// inside another law's entry and reported beside that law's verdict, never as it.
///
/// **Only #671's dedupe count laws use this today**, C1 (a singleton survives) and C2 (a
/// duplicate of everything adds nothing), riding on a dedupe's `idempotence` entry. They are
/// not idempotence. A C2 failure filed as `measured-defaultFails` would read as *idempotence
/// refuted*, veto the row, bank an idempotence regression test and seed the replay corpus with
/// a counterexample idempotence passes. So the stub runs them after idempotence holds, prints
/// their own markers (`VERIFY_DEFAULT_LAW_<law>_*`) and never exits, and the verdict stays
/// idempotence's.
///
/// **Not a back door for piling laws onto an entry.** A companion is a law the accepted stub
/// already writes for this row, which verify then checks so the two cannot disagree
/// (`InteractiveTriage+AcceptEntailedLaws`). Adding one needs that, not just a reason to check
/// more.
public struct CompanionLawOutcome: Sendable, Equatable, Codable {

    public enum Status: String, Sendable, Codable {
        case held
        case failed
        /// The law began and never reported: the process trapped inside it.
        case trapped
    }

    /// The law's short name as the stub prints it, `C1` or `C2`.
    public let law: String
    public let status: Status
    /// The failing trial, input and output, when `status == .failed`.
    public let trial: Int?
    public let input: String?
    public let output: String?

    public init(law: String, status: Status, trial: Int? = nil, input: String? = nil, output: String? = nil) {
        self.law = law
        self.status = status
        self.trial = trial
        self.input = input
        self.output = output
    }

    /// A refutation: the law failed or trapped. It withholds the primary law's promotion.
    ///
    /// **Every companion result binds; there is no advisory one.** The stub runs each law once,
    /// on the primary law's default generator, after both of the primary law's passes. The
    /// accepted stub has no edge pass, so agreement needs none, and a companion run inside the edge
    /// pass could trap there and turn the primary law's verdict into an error (#734's second review).
    public var refutes: Bool { status != .held }

    /// What #671 says each law catches, for the rendered line.
    public var statement: String {
        switch law {
        case "C1": "a singleton survives (`f([x]).count == 1`)"

        case "C2": "a duplicate of everything adds nothing (`f(xs + xs)` vs `f(xs)`)"

        default: law
        }
    }

    /// One line for a human: `C2 FAILED at trial 3: … — input …, output …`.
    public var rendered: String {
        switch status {
        case .held:
            return "\(law) held: \(statement)"

        case .trapped:
            return "\(law) TRAPPED: \(statement)"

        case .failed:
            let at = trial.map { " at trial \($0)" } ?? ""
            let detail = [input.map { "input \($0)" }, output.map { "output \($0)" }]
                .compactMap(\.self).joined(separator: ", ")
            return "\(law) FAILED\(at): \(statement)" + (detail.isEmpty ? "" : " — \(detail)")
        }
    }
}

public extension [CompanionLawOutcome] {
    /// The first refutation, or `nil` when every companion held.
    var refutation: CompanionLawOutcome? { first(where: \.refutes) }
}
