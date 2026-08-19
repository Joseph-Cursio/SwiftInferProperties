import Foundation
import Testing

/// **Can §6.3's soundness arm be built from what this toolchain already has?**
///
/// `plans/declaration-claims-plan.md` §6.5 prices the whole empirical arm on one
/// sentence: *"`VerifierSubprocess` already runs each law as its own process with
/// `DYLD_*` injection — process isolation exists and **the interposition hook is in
/// place**, which is what makes report-rather-than-kill cheap."*
///
/// Half of that is true. The hook is not there, and the arm needs a detector before it
/// needs anything else — so this suite measures the detector rather than assuming it,
/// which is the practice `docs/measurements/ownership-premise-declined.md` established
/// after two Family C rows were scoped on premises that read plausibly and measured
/// false.
///
/// ## What is measured, and why each one decides something
///
/// 1. **The hook is absent** — a filesystem fact, pinned so it fails the day it stops
///    being one. §6.5's cost estimate is wrong while it holds.
/// 2. **Seatbelt denies what an unsandboxed run allows, and the process SURVIVES.**
///    §6.1's hard constraint — *"the denial must report which policy fired, not kill
///    the process"* — because a sandbox refuting by `SIGKILL` reproduces
///    `#assertIdempotent`'s trapping `precondition` one layer down and leaves no
///    output. Measured: it is free, no dylib required.
/// 3. **The errno names the policy for two classes of three, and lies for the third.**
///    A denied `process-exec` surfaces as *"the file doesn't exist"*, not as a
///    permission error — and a subprocess spawn is what the answer key's sharpest row
///    (`DrainedProcess.standardOutputViaEnv`) actually does.
/// 4. **An allow-list is partial inside its own subpath.** A non-atomic write to an
///    explicitly allowed directory succeeds; `String.write(atomically: true)` and
///    `FileManager.createFile` in the same directory are denied. So a probe's own
///    plumbing can trip the detector, which is why the arm's control set is
///    load-bearing rather than a formality.
///
/// ## The unsandboxed arm is the control, not a warm-up
///
/// Every sandboxed expectation here is a *denial*, and a denial is indistinguishable
/// from a probe that never ran. This repo's confident-zero rule applies directly: the
/// same binary is run with no profile first, and every step must be ALLOWED there. A
/// scan that reaches nothing passes, so the denominator is asserted.
///
/// ## Deliberately not measured
///
/// **Whether a trip is informative.** `docs/measurements/soundness-arm-reach.md` draws
/// this line already: reach is a precondition, not a result. This suite measures the
/// detector's mechanism over a probe written for the purpose, and says nothing about
/// the 2,396 `.pure` subjects.
///
/// **Outbound network.** The loopback `connect` below reaches port 1 on `127.0.0.1`
/// and no packet leaves the machine. The original spike used an HTTP fetch; a test
/// suite that makes outbound requests measures the network, so it was replaced once
/// `ECONNREFUSED` vs `EPERM` was shown to separate the two cases cleanly.
@Suite("Census — can the soundness arm's sandbox be built from what the toolchain has?", .serialized)
struct SandboxDetectorMechanismMeasuredTests {

    // MARK: - 1 · The interposition hook

    /// **Inverted the day the hook lands.** `DYLD_LIBRARY_PATH` is a *search path* for
    /// `libTesting.dylib`; `DYLD_INSERT_LIBRARIES` is an interposition hook. §6.5 reads
    /// the first as the second, and the difference is the entire cost of the arm.
    ///
    /// The positive control is what makes the zeros readable: `DYLD_LIBRARY_PATH` must
    /// be found, or the scan is looking in the wrong place and every absence below is
    /// an artifact — the *blind detector* failure
    /// `docs/measurements/module-state-base-rate.md` published a zero from.
    @Test("no interposition hook exists, and the scan that says so is not blind")
    func theInterpositionHookIsNotInPlace() throws {
        let hits = try Self.scanSwiftSources()

        #expect(hits["DYLD_LIBRARY_PATH"] ?? 0 > 0, """
        Positive control failed: `DYLD_LIBRARY_PATH` was not found in any Swift source. \
        The scan is not reaching `VerifierSubprocess`, so the zeros below mean nothing.
        """)

        for needle in Self.hookNeedles {
            #expect(hits[needle] == 0, """
            `\(needle)` now appears in the package. If an interposition hook has landed, \
            §6.5 of `plans/declaration-claims-plan.md` has become true and \
            `docs/measurements/sandbox-detector-mechanism.md` must be re-read before its \
            recommendation is followed.
            """)
        }

        #expect(Self.nonSwiftSourceFiles().isEmpty, """
        `Sources/` now contains a non-Swift source file. An interposing dylib needs one, \
        so this is the other way the finding above stops holding.
        """)
    }

    // MARK: - 2 · Denial, and survival

    /// The whole mechanism question in one comparison. `unsandboxed` is the control;
    /// `denyAll` is the detector.
    @Test("seatbelt denies what an unsandboxed run allows, and the probe survives every denial")
    func theSandboxDeniesWhatTheUnsandboxedRunAllows() throws {
        let probe = try Self.ProbeBinary()

        let open = try probe.run(profile: nil)
        for step in Probe.Step.allCases {
            #expect(open[step]?.allowed == true, """
            Control failed: `\(step.rawValue)` was not permitted with NO sandbox profile. \
            A denial below would then be unreadable — it could equally mean the probe \
            cannot do the thing at all.
            """)
        }

        let denied = try probe.run(profile: probe.denyAllProfile)
        for step in Probe.Step.allCases {
            #expect(denied[step]?.allowed == false, "`\(step.rawValue)` was not denied under deny-all.")
        }

        #expect(denied.completed, """
        The probe did not reach its final line under the deny-all profile. §6.1's \
        report-rather-than-kill constraint is the one that cannot be worked around: a \
        sandbox that refutes by killing destroys the counterexample.
        """)
    }

    // MARK: - 3 · What the denial says about itself

    /// **`process-exec` is the class that lies, and it is the class that matters.**
    /// The answer key's sharpest row spawns a subprocess, so a probe reading only the
    /// thrown error would file the arm's best finding as a missing binary.
    @Test("the errno names the policy for file-write and network, and not for process-exec")
    func theDeniedOperationDoesNotAlwaysNameThePolicy() throws {
        let probe = try Self.ProbeBinary()
        let denied = try probe.run(profile: probe.denyAllProfile)

        #expect(denied[.writeOutside]?.detail == Int(EPERM), """
        A denied file write no longer reports EPERM. The differential-profile design in \
        `docs/measurements/sandbox-detector-mechanism.md` was chosen because ONE class \
        already misreported; if a second has joined it, re-take the table.
        """)
        #expect(denied[.connectLoopback]?.detail == Int(EPERM))

        #expect(denied[.spawn]?.detail != Int(EPERM), """
        A denied `process-exec` now reports EPERM. That would be an improvement, and it \
        retires the reason attribution needs differencing rather than the thrown error.
        """)
    }

    // MARK: - 4 · The allow-list is partial

    /// Same directory, three ways of writing to it, two of them denied by a rule that
    /// names that directory. This is the finding the arm's control set exists to catch.
    @Test("an allowed subpath admits a plain write and refuses an atomic one")
    func theAllowListIsPartialInsideItsOwnSubpath() throws {
        let probe = try Self.ProbeBinary()
        let scoped = try probe.run(profile: probe.allowWorkdirProfile)

        #expect(scoped[.writeInsideNonAtomic]?.allowed == true, """
        The `(allow file-write* (subpath …))` rule no longer admits even a plain write. \
        The profile is then denying its own workdir outright and nothing below is readable.
        """)
        #expect(scoped[.writeInsideAtomic]?.allowed == false)
        #expect(scoped[.createFileInside]?.allowed == false)

        #expect(scoped[.writeOutside]?.allowed == false, """
        The workdir allow leaked outside its subpath, which would make the detector \
        useless in the direction it is actually for.
        """)
        #expect(scoped[.spawn]?.allowed == false)
    }
}
