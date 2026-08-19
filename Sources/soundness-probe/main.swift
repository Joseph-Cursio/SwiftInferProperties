import Foundation

// **`#if DEBUG` wraps everything below, and it is not tidiness.** Five of the nine
// subjects are `internal`, so the probe needs `@testable` — which requires
// `-enable-testing`, which a RELEASE build does not have. Without this guard
// `swift build -c release` fails outright with *"module 'SwiftInferCLI' was not compiled
// for testing"*, and it did: the target shipped in that state because `make test` builds
// only debug, so nothing in the suite ever release-built the package.
//
// The probe is a debug-only instrument by nature — it exists to be run under a sandbox by
// a measured test — so losing it in release costs nothing. The stub keeps the target
// linkable and says why.
#if DEBUG

@testable import SwiftInferCLI
@testable import SwiftInferCore

/// The probe, as a type: `main.swift` may not declare top-level constants
/// (`prefixed_toplevel_constant`), and a `k`-prefixed global is worse than a namespace.
enum SoundnessProbe {

    // Phase 0.5's soundness arm, step 1: invoke the nine strictly-reachable rows of the frozen
    // trip list, plus a control set, and print a fingerprint of each result.
    //
    // **The detector is DIFFERENTIAL, and it has to be.** These functions swallow failure:
    // `KitEvidenceStore.load` returns an empty log whether the file is absent or the read was
    // denied, so a sandbox denial is invisible in the return value. What is visible is a
    // *difference* between the sandboxed and unsandboxed runs — and a pure function's result
    // cannot depend on a resource that was denied.
    //
    // The harness owns the comparison. This binary's only job is to be deterministic about
    // what it prints, one subject per line, so two runs can be diffed.

    /// A subject's result, reduced to a string the harness can compare across runs.
    struct Probe: Sendable {
        let name: String
        let run: @Sendable () -> String
    }

    // The directory every subject is pointed at. **A POPULATED fixture, passed in, not a
    // scratch temp dir** — the first run of this probe used an empty one and eight of nine
    // subjects returned the same empty result sandboxed and unsandboxed, because there was
    // nothing to read either way. `soundness-arm-reach.md` predicted exactly that: *"a
    // function reading a package manifest under a temp URL returns nil rather than doing
    // anything interesting."* Reach is not exercise.
    static let temp = URL(fileURLWithPath: CommandLine.arguments.count > 1
        ? CommandLine.arguments[1]
        : NSTemporaryDirectory())

    // MARK: - The trip list's nine strictly-reachable rows

    static let tripList: [Probe] = [
        Probe(name: "DependencyTypeShapes.scan") {
            let scanned = DependencyTypeShapes.scan(packageRoot: temp, localTypeNames: [])
            return "shapes=\(scanned.shapes.count) roots=\(scanned.roots.count) collisions=\(scanned.collisions.count)"
        },
        Probe(name: "Metrics.loadAggregate") {
            let result = SwiftInferCommand.Metrics.loadAggregate(directoryOverride: temp.path, explicitPaths: [])
            return "decisions=\(result.decisions.records.count)"
        },
        Probe(name: "MetricsInteraction.loadDecisions") {
            let loaded = SwiftInferCommand.MetricsInteraction.loadDecisions(
                directoryOverride: temp.path, explicitPaths: []
            )
            return "records=\(loaded.decisions.records.count) sources=\(loaded.sources.count) "
            + "warnings=\(loaded.warnings.count)"
        },
        Probe(name: "SpeculativeRefactorRunner.scanRestricted") {
            let scan = SpeculativeRefactorRunner.scanRestricted(under: temp)
            return "restricted=\(scan.restricted.count) files=\(scan.sourcesByFile.count)"
        },
        Probe(name: "VerifierWorkdir.macOSPlatformLine") {
            VerifierWorkdir.macOSPlatformLine(userPackage: nil)
        },
        Probe(name: "ViewModelArgumentGenerator.candidateValuesExpression") {
            ViewModelArgumentGenerator.candidateValuesExpression(for: "Int") ?? "nil"
        },
        Probe(name: "EffectResolver.resolve") {
            "summaries=\(EffectResolver.resolve(summaries: [], in: temp).count)"
        },
        Probe(name: "KitEvidenceStore.load") {
            "outcomes=\(KitEvidenceStore.load(startingFrom: temp).outcomes.count)"
        },
        Probe(name: "DrainedProcess.standardOutputViaEnv") {
            let data = DrainedProcess.standardOutputViaEnv(["echo", "probe"])
            return "bytes=\(data?.count ?? -1)"
        }
    ]

    // MARK: - Controls

    /// **Genuinely pure functions, and the arm is unreadable without them.** Every trip-list
    /// reading is a *difference between two runs*; a control that also differs would mean the
    /// harness is measuring the sandbox's effect on the runtime rather than on the subject.
    static let controls: [Probe] = [
        Probe(name: "control/SubjectFingerprint.of") {
            SubjectFingerprint.of(bodyText: "let x = 1")
        },
        Probe(name: "control/SuggestionIdentity") {
            SuggestionIdentity(canonicalInput: "predicate::isEmpty").display
        },
        Probe(name: "control/candidateValuesExpression-String") {
            ViewModelArgumentGenerator.candidateValuesExpression(for: "String") ?? "nil"
        }
    ]

    // MARK: - Run

    static func run() {
        for probe in controls + tripList {
            print("\(probe.name)|\(probe.run())")
        }
        print("PROBE COMPLETED")
    }
}

SoundnessProbe.run()

#else

print("soundness-probe is a DEBUG-only instrument: it needs `@testable` to reach the "
    + "internal subjects on the trip list, which a release build cannot provide.")

#endif
