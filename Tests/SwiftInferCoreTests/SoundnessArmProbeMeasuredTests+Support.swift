import Foundation
import SwiftEffectInference
import Testing

@testable import SwiftInferCore
@testable import SwiftInferTemplates

/// Locating, running and diffing the probe for `SoundnessArmProbeMeasuredTests`. Split out
/// only for the 400-line file cap; the reasoning that governs both lives in that suite's
/// header.
extension SoundnessArmProbeMeasuredTests {

    struct Readings {
        let open: [String: String]
        let denied: [String: String]

        var subjects: Int { open.count }

        /// Subjects whose fingerprint differs between the arms — the trips.
        var tripped: [String] {
            open.filter { denied[$0.key] != $0.value }.keys.sorted()
        }
    }

    static let packageRoot = PurityRefutationCensusMeasuredTests.packageRoot

    static let fixture = packageRoot.appendingPathComponent("fixtures/soundness-probe")

    /// The probe binary, under whatever triple SwiftPM built into. Globbed rather than
    /// hardcoded so an arm64/x86 host difference does not read as "the arm found nothing".
    static let binary: URL? = {
        let build = packageRoot.appendingPathComponent(".build")
        guard let triples = try? FileManager.default.contentsOfDirectory(
            at: build, includingPropertiesForKeys: nil
        ) else { return nil }
        for triple in triples {
            let candidate = triple.appendingPathComponent("debug/soundness-probe")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }()

    /// **`realpath`, for the same reason the mechanism census needed it.** Seatbelt matches
    /// a `(literal …)` against the canonical path, and Foundation's
    /// `resolvingSymlinksInPath()` strips `/private` rather than adding it — so an
    /// unresolved path makes the profile's own allow miss the probe, the exec is denied,
    /// and the run comes back empty. Which reads exactly like a sandbox that denied
    /// everything.
    static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    /// Deny reads of the **fixture subpath only**, plus writes, network and exec.
    ///
    /// Reads are denied narrowly on purpose: a global read denial stops `dyld` before the
    /// probe's first line, which measures the runtime rather than the subject.
    static func denyProfile(binary: String, fixture: String) -> String {
        """
        (version 1)
        (allow default)
        (deny file-read* (subpath "\(fixture)"))
        (deny file-write*)
        (deny network*)
        (deny process-exec*)
        (allow process-exec (literal "\(binary)"))
        """
    }

    static let readings: Readings? = {
        guard let binary, FileManager.default.fileExists(atPath: fixture.path) else { return nil }
        let canonicalBinary = canonical(binary.path)
        let canonicalFixture = canonical(fixture.path)

        guard let open = run(binary: binary, profile: nil) else { return nil }

        let profilePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("soundness-arm-profile.sb")
        let profile = denyProfile(binary: canonicalBinary, fixture: canonicalFixture)
        guard (try? profile.write(to: profilePath, atomically: true, encoding: .utf8)) != nil,
              let denied = run(binary: binary, profile: profilePath.path) else { return nil }

        return Readings(open: open, denied: denied)
    }()

    /// One run, parsed into `subject → fingerprint`. `nil` when the probe did not reach its
    /// final line — a partial run diffed against a complete one manufactures trips.
    static func run(binary: URL, profile: String?) -> [String: String]? {
        let process = Process()
        if let profile {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-f", profile, binary.path, fixture.path]
        } else {
            process.executableURL = binary
            process.arguments = [fixture.path]
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        guard output.contains("PROBE COMPLETED") else { return nil }

        var readings: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            readings[String(parts[0])] = String(parts[1])
        }
        return readings
    }
}

// MARK: - Do the arm's findings have a consumer?

extension SoundnessArmProbeMeasuredTests {

    /// The four subjects the arm confirmed depend on state the sandbox can take away.
    /// Keyed by **file and name**: `load` and `resolve` each match several declarations
    /// here, and name-keying has been the dominant defect at this seam in three
    /// measurements.
    static let confirmedImpure: [(file: String, name: String)] = [
        (file: "DrainedProcess.swift", name: "standardOutputViaEnv"),
        (file: "KitEvidenceStore.swift", name: "load"),
        (file: "MetricsInteractionCommand.swift", name: "loadDecisions"),
        (file: "SpeculativeRefactorRunner+Machinery.swift", name: "scanRestricted")
    ]

    struct Carried {
        let subject: String
        let verdict: PurityVerdict
        let template: String
        let tier: String
        let vetoed: Bool
    }

    /// Suggestions whose evidence rests on one of the confirmed-impure four.
    static let carried: [Carried] = carriedRows(matching: confirmedImpure)

    /// The join, reusable so the non-vacuity control can run the *same* machinery over a
    /// target set known to carry laws.
    static func carriedRows(matching wanted: [(file: String, name: String)]) -> [Carried] {
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        guard let scanned = try? FunctionScanner.scanCorpus(directory: root) else { return [] }

        let targets = Dictionary(
            scanned.summaries.compactMap { summary -> (SwiftInferCore.SourceLocation, FunctionSummary)? in
                let file = URL(fileURLWithPath: summary.location.file).lastPathComponent
                guard wanted.contains(where: { $0.file == file && $0.name == summary.name })
                else { return nil }
                return (summary.location, summary)
            }
        ) { first, _ in first }

        let suggestions = TemplateRegistry.discover(
            in: scanned.summaries, identities: scanned.identities, typeDecls: scanned.typeDecls
        )
        return suggestions.flatMap { suggestion -> [Carried] in
            suggestion.evidence.compactMap { row -> Carried? in
                guard let summary = targets[row.location] else { return nil }
                return Carried(
                    subject: "\(summary.name) @ \(URL(fileURLWithPath: summary.location.file).lastPathComponent)",
                    verdict: summary.purityVerdict,
                    template: suggestion.templateName,
                    tier: "\(suggestion.score.tier)",
                    vetoed: suggestion.score.signals.contains { $0.kind == .impureSubject && $0.isVeto }
                )
            }
        }
    }

    /// **The control.** All four must be present in the scan, or an absent row would read
    /// as "carries no law" — the confident zero, in the census asking whether anything
    /// consumes the arm's output.
    @Test("control — all four confirmed subjects are in the scanned corpus")
    func theConfirmedFourAreScanned() {
        let root = PurityRefutationCensusMeasuredTests.packageSourcesRoot
        let scanned = (try? FunctionScanner.scanCorpus(directory: root))?.summaries ?? []
        for target in Self.confirmedImpure {
            #expect(scanned.contains { summary in
                URL(fileURLWithPath: summary.location.file).lastPathComponent == target.file
                    && summary.name == target.name
            }, "\(target.name) is no longer in Sources/ — the trip list needs re-freezing")
        }
    }

    /// **The question the Decisions stub says to ask of any output value.** The arm found
    /// four false `.pure`. The veto ships on *witness-refuted* subjects — and these are
    /// `.pure`, so nothing refutes them and the veto never sees them.
    @Test("census — do the arm's confirmed findings carry laws today?")
    func theArmsFindingsConsumer() {
        print("ARM FINDINGS → LAWS: \(Self.carried.count) suggestion row(s)")
        for row in Self.carried.sorted(by: { $0.subject < $1.subject }) {
            let line = "    \(row.subject) · verdict=\(row.verdict) · \(row.template)"
            print(line + " · tier=\(row.tier) · vetoed=\(row.vetoed)")
        }
    }
}

extension SoundnessArmProbeMeasuredTests {

    /// Subjects known to carry laws — `docs/measurements/purity-veto-precision.md` lists
    /// them among the veto's eight witness-scoped removals.
    static let knownToCarryLaws: [(file: String, name: String)] = [
        (file: "TargetDirectory+Inference.swift", name: "directoryExists"),
        (file: "VocabularyLoader.swift", name: "fileExists")
    ]

    /// **Non-vacuity, and it is the whole warrant for the zero above.** The same join
    /// machinery, pointed at subjects that demonstrably carry suggestions, must find them.
    /// A dictionary built on the wrong key, or an evidence row whose location never
    /// matches, reports "no law rests on the arm's findings" just as convincingly as the
    /// truth does — and that is this repo's confident zero in the census whose entire
    /// output is a zero.
    @Test("control — the join finds laws when there are laws to find")
    func theJoinIsNotBlind() {
        let found = Self.carriedRows(matching: Self.knownToCarryLaws)
        #expect(!found.isEmpty, """
        The join found no suggestion resting on `directoryExists` or `fileExists`, which \
        the veto census measures as carrying laws. The zero reported for the arm's \
        confirmed-impure four is therefore the instrument's, not the corpus's.
        """)
    }
}
