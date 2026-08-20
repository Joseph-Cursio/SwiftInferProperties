import Foundation
import Testing

/// **Phase 0.5, step 1 — does the sandbox distinguish the trip list from pure controls?**
///
/// `docs/plans/declaration-claims-plan.md` §6.3 puts this first and says why: *"if the
/// sandbox cannot distinguish those nine from a control set of genuinely pure functions,
/// it does not work and nothing else matters."*
///
/// ## The detector is differential, and it has to be
///
/// These subjects **swallow failure**. `KitEvidenceStore.load` returns an empty log
/// whether the file is absent or the read was denied, so a denial is invisible in the
/// return value — the mechanism census
/// (`docs/measurements/sandbox-detector-mechanism.md`) measured that the errno often does
/// not name the policy either, and that no log channel carries it.
///
/// What *is* visible is a **difference between two runs of the same binary**: a pure
/// function's result cannot depend on a resource that was denied. So the probe prints one
/// fingerprint per subject and the harness diffs the runs.
///
/// ## Two things the first run of this measured, both worth keeping
///
/// **A degenerate argument reaches a function without exercising it.** Pointed at an empty
/// temp directory, eight of the nine returned the same empty result either way — there was
/// nothing to read in both arms. `docs/measurements/soundness-arm-reach.md` predicted this
/// in as many words: *"a function reading a package manifest under a temp URL returns nil
/// rather than doing anything interesting."* **Reach is not exercise**, and the fixture is
/// what closes the gap.
///
/// **Denying writes finds nothing, because these subjects read.** The profile denies reads
/// *of the fixture subpath only* — denying reads globally would stop `dyld` and measure
/// the runtime rather than the subject.
@Suite("Census — phase 0.5's soundness arm, the nine reachable rows", .serialized)
struct SoundnessArmProbeMeasuredTests {

    @Test("control — the probe binary is built and both arms ran")
    func theProbeRan() throws {
        let readings = try #require(Self.readings, Self.unavailable)
        #expect(readings.open.count >= 12, "only \(readings.open.count) subjects reported")
        #expect(readings.open.keys.sorted() == readings.denied.keys.sorted(), """
        The two arms reported different subject sets, so the diff below is comparing \
        runs that did not do the same work.
        """)
    }

    /// **The control set is what makes a difference readable.** If a genuinely pure
    /// function also differed, the harness would be measuring the sandbox's effect on the
    /// Swift runtime rather than on the subject.
    @Test("control — no pure control differs between the arms")
    func controlsAreStable() throws {
        let readings = try #require(Self.readings, Self.unavailable)
        for (name, value) in readings.open where name.hasPrefix("control/") {
            #expect(readings.denied[name] == value, """
            Pure control `\(name)` changed under the sandbox: \(value) → \
            \(readings.denied[name] ?? "<absent>"). Every trip below is then suspect — the \
            profile is reaching the runtime, not the subject.
            """)
        }
    }

    /// The arm's reason for existing: the inferrer calls these `.pure` and at least one
    /// demonstrably depends on state the sandbox can take away.
    @Test("the arm separates the trip list from the controls")
    func theArmSeparates() throws {
        let readings = try #require(Self.readings, Self.unavailable)
        #expect(!readings.tripped.isEmpty, """
        No subject differed between the arms, so the sandbox distinguishes nothing and \
        §6.3's precondition fails — nothing else in phase 0.5 matters until it does.
        """)
        #expect(readings.tripped.allSatisfy { !$0.hasPrefix("control/") })
    }

    @Test("census — which of the nine trip")
    func census() throws {
        let readings = try #require(Self.readings, Self.unavailable)
        print("SOUNDNESS ARM PROBE — \(readings.tripped.count) tripped of \(readings.subjects) subjects")
        for name in readings.open.keys.sorted() {
            let before = readings.open[name] ?? "?"
            let after = readings.denied[name] ?? "?"
            let mark = before == after ? "  " : "TRIP"
            print("  \(mark) \(name)\n         open: \(before)\n       denied: \(after)")
        }
    }

    static let unavailable: Comment = """
    The `soundness-probe` executable was not found. It is built by `swift build`, which \
    `make test` runs ahead of the suites — build the package before running this census.
    """
}
