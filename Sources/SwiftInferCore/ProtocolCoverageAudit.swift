import Foundation

/// **Is the coverage veto's premise actually true?**
///
/// `ProtocolCoverageMap` suppresses a template when the carrier's conformances mean
/// PropertyLawKit already checks that law. Its own doc states the justification outright:
/// *"the kit's `check<Protocol>PropertyLaws` **does** verify the property the template would
/// have emitted."*
///
/// That is a claim about a **downstream package the project may not depend on**, and nothing
/// checked it. `protocolCoverageVeto` takes only `(summary, inheritedTypesByName)`; no code
/// path reads `Package.swift` for SwiftPropertyLaws. So the veto is **unconditional while
/// the coverage it assumes is conditional on adoption**, and the failure is silent in the
/// worst way: the veto's job is to prevent double-reporting, so its success looks exactly
/// like there being nothing to report.
///
/// Concretely, on a project with no kit dependency: a type conforms to `Equatable`, the
/// Equatable laws are vetoed, the kit never runs, and **nothing checks them at all**.
///
/// ## Why this audits rather than flipping the veto
///
/// Un-vetoing on absent evidence would be wrong in both directions. Most projects have no
/// `kit-evidence.json`, so "absent" is the normal state, not a signal — flipping there would
/// re-admit every conformance-covered law on every project at once, which is the Daikon
/// flood the PRD's §3.5 corollary exists to prevent. And the fix for too much output is to
/// raise thresholds, not to add filters, so trading silence for a flood is not an
/// improvement.
///
/// What is genuinely fixable is the **silence**. A reader cannot currently tell the
/// difference between "the kit covers this" and "we assumed the kit covers this and it does
/// not exist." This makes that difference visible without changing a single grade.
///
/// ## What this counts, and what it deliberately does NOT
///
/// **It counts carriers whose conformances the kit's suites cover. It does NOT count laws
/// that were actually suppressed, and its first version claimed to.**
///
/// That claim was measured false immediately: this audit reported *"150 carrier(s) had laws
/// suppressed"* on `SwiftInferCore`, where running `discover` with the veto disabled returns
/// **exactly the same 96 suggestions** as with it enabled. Zero were suppressed. Across six
/// corpora — this repo's three targets, `leaderboard-sort`, `SwiftPropertyLaws` and
/// `SwiftEffectInference` — the veto suppresses **1 suggestion out of ~300**.
///
/// Knowing the true figure needs the veto to *record* when it fires, which needs the
/// evidence threaded to the veto site through seven templates. Rather than ship a proxy
/// dressed as a measurement, the wording states what is actually known: these carriers have
/// conformances whose laws the kit's suites check, so **if the kit is not running, those
/// laws are checked by nothing** — true regardless of whether `discover` would have
/// proposed one.
///
/// The near-inertness is itself the more interesting finding, and it cuts against the
/// argument originally given for auditing rather than un-vetoing: there is no flood to
/// prevent. Un-vetoing would re-admit one law across six corpora. The veto is close to a
/// no-op, which means the case for changing its behaviour is weak in *both* directions and
/// the honest contribution here is the visibility, not the guard.
///
/// The three states are deliberately distinct, and `wasExercised` alone cannot separate the
/// last two — `wasExercised(T)` is false both when the kit never ran and when it ran on
/// other types but not `T`. The emptiness of the log is what tells them apart.
public enum ProtocolCoverageAudit {

    /// What the evidence says about one vetoed carrier.
    public enum Standing: String, Sendable, Equatable {
        /// Kit evidence exists and names this type. The veto's premise is **verified**.
        case verified
        /// No kit evidence at all. The premise is **assumed** — the normal state, and not by
        /// itself a defect.
        case assumed
        /// Kit evidence exists and does **not** name this type. The project demonstrably uses
        /// the kit and demonstrably did not run it here, so the premise is **contradicted**
        /// for this carrier specifically. The sharp case.
        case contradicted
    }

    public struct Finding: Sendable, Equatable {
        public let typeName: String
        /// The conformance that triggers the veto — `"Equatable"`.
        public let coveringConformance: String
        public let standing: Standing

        public init(typeName: String, coveringConformance: String, standing: Standing) {
            self.typeName = typeName
            self.coveringConformance = coveringConformance
            self.standing = standing
        }
    }

    /// Every carrier whose conformances would trigger a coverage veto, with what the kit
    /// evidence says about it.
    ///
    /// Recomputed from the conformance index rather than recorded during template runs —
    /// the same inputs the veto itself uses, so it cannot drift from the decision it audits,
    /// and it needs no evidence threaded through seven templates to reach the veto site.
    public static func audit(
        inheritedTypesByName: [String: Set<String>],
        kitEvidence: KitEvidenceLog
    ) -> [Finding] {
        let hasAnyEvidence = !kitEvidence.outcomes.isEmpty
        return inheritedTypesByName.keys.sorted().compactMap { typeName -> Finding? in
            // Skip the curated stdlib bake-in. `inheritedTypesIndex` merges it in, so a
            // two-type file audited to 22 carriers — Array, Bool, Dictionary and friends —
            // on the first run. Reporting those is worse than noise: the kit demonstrably
            // DOES cover `Array`, so naming it as unchecked is a false alarm, and the reader
            // cannot act on it either way because it is not their code.
            guard ProtocolCoverageMap.stdlibConformances[typeName] == nil else { return nil }
            guard let conformances = inheritedTypesByName[typeName],
                  let covering = conformances.sorted().first(where: {
                      ProtocolCoverageMap.protocolCoverage[$0] != nil
                  }) else {
                return nil
            }
            let standing: Standing
            if !hasAnyEvidence {
                standing = .assumed
            } else if kitEvidence.wasExercised(typeName) {
                standing = .verified
            } else {
                standing = .contradicted
            }
            return Finding(
                typeName: typeName,
                coveringConformance: covering,
                standing: standing
            )
        }
    }

    /// Run-level lines for the caller to emit, or empty when there is nothing worth saying.
    ///
    /// **Only `.contradicted` speaks per-carrier.** `.assumed` is the normal state on a
    /// project that has never exported kit results, and a warning per type would be noise on
    /// every run — the same reason `TargetDirectory.warnIfEmpty` prints only in the empty
    /// case. It gets one aggregate line instead, and only when something was actually
    /// vetoed.
    public static func diagnostics(for findings: [Finding]) -> [String] {
        var lines: [String] = []

        let contradicted = findings.filter { $0.standing == .contradicted }
        if !contradicted.isEmpty {
            let named = contradicted.prefix(5).map(\.typeName).joined(separator: ", ")
            let more = contradicted.count > 5 ? " (+\(contradicted.count - 5) more)" : ""
            lines.append(
                "\(contradicted.count) carrier(s) have conformances whose laws PropertyLawKit "
                    + "checks — and your kit evidence does not mention them: \(named)\(more). "
                    + "The kit ran on other types and not these, so those laws are currently "
                    + "checked by nothing. Run the matching check<Protocol>PropertyLaws suite "
                    + "on them. (This counts CARRIERS, not suppressed suggestions — see "
                    + "`ProtocolCoverageAudit`; the veto itself is close to a no-op.)"
            )
        }

        let assumed = findings.filter { $0.standing == .assumed }
        if !assumed.isEmpty {
            lines.append(
                "\(assumed.count) carrier(s) have conformances whose laws PropertyLawKit "
                    + "checks, and there is no kit evidence saying it ran. Normal if you run "
                    + "the kit and have not exported results; a real gap if you do not depend "
                    + "on SwiftPropertyLaws at all, because then nothing checks those laws — "
                    + "and every one of them has an explicit suite you could run. Export "
                    + "results to `.swiftinfer/kit-evidence.json` to turn this into a check."
            )
        }
        return lines
    }
}
