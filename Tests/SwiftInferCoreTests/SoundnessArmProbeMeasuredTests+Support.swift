import Foundation

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
