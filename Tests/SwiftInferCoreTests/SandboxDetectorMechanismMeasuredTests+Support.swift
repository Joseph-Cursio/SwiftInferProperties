import Foundation

/// The probe, its profiles, and the source scan for
/// `SandboxDetectorMechanismMeasuredTests`. Split out only for the 400-line file cap;
/// the reasoning that governs both lives in that suite's header.
extension SandboxDetectorMechanismMeasuredTests {

    // MARK: - The source scan

    /// Spellings that would make §6.5's *"the interposition hook is in place"* true.
    /// `DYLD_LIBRARY_PATH` is deliberately **not** here — it is the positive control,
    /// and conflating the search path with the hook is the error being pinned.
    static let hookNeedles = ["DYLD_INSERT_LIBRARIES", "__interpose", "dlopen(", "dlsym("]

    static let packageRoot = PurityRefutationCensusMeasuredTests.packageRoot

    /// This suite's own two files, excluded by name.
    ///
    /// **A guard for an absence has to spell the thing that is absent**, so both files
    /// below contain every needle in their prose and would report themselves forever.
    /// `DocCitationTests` solved the identical problem the identical way — by name
    /// (`selfDescribingFiles`) rather than by a "is it inside a comment" rule, because
    /// the spelling is prose here as often as it is code.
    ///
    /// It cost the first run of this suite four false hits, which is the cheapest
    /// possible demonstration that the scan reaches the files it claims to.
    static let selfDescribingFiles: Set<String> = [
        "SandboxDetectorMechanismMeasuredTests.swift",
        "SandboxDetectorMechanismMeasuredTests+Support.swift"
    ]

    /// Occurrence counts for every needle plus the control, over `Sources/` and
    /// `Tests/`. Counted rather than existence-checked so the control can assert a
    /// number greater than zero and the needles a number equal to it.
    static func scanSwiftSources() throws -> [String: Int] {
        var counts = [String: Int](uniqueKeysWithValues: (hookNeedles + ["DYLD_LIBRARY_PATH"]).map { ($0, 0) })

        for root in ["Sources", "Tests"] {
            let directory = packageRoot.appendingPathComponent(root)
            for file in swiftFiles(under: directory)
            where !selfDescribingFiles.contains(file.lastPathComponent) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for needle in counts.keys where text.contains(needle) {
                    counts[needle, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// A non-Swift source file under `Sources/` — what an interposing dylib would need.
    /// Resource files carry no compiler behaviour, so only compilable extensions count.
    static func nonSwiftSourceFiles() -> [String] {
        let compilable: Set<String> = ["c", "m", "mm", "cc", "cpp", "h", "hpp", "s"]
        let sources = packageRoot.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { element in
            guard let url = element as? URL, compilable.contains(url.pathExtension.lowercased()) else { return nil }
            return url.lastPathComponent
        }
    }

    private static func swiftFiles(under directory: URL) -> [URL] {
        guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return walker.compactMap { element in
            guard let url = element as? URL, url.pathExtension == "swift" else { return nil }
            return url
        }
    }
}

// MARK: - The probe's vocabulary

/// A failure in the harness itself, never a finding. Kept distinct from a denial so a
/// compiler that could not run is never reported as a sandbox that denied everything —
/// the two look identical in a results table and mean opposite things.
enum ProbeError: Error {
    case compilationFailed(String)
    case launchFailed(String)
}

/// One operation the probe attempts, and what the run made of it.
///
/// `ALLOWED` means *the policy permitted the syscall*, which is why a loopback
/// `connect` refused with `ECONNREFUSED` counts as allowed: the sandbox let it through
/// and nothing was listening. Only `EPERM` is a denial.
enum Probe {

    enum Step: String, CaseIterable {
        case writeInsideAtomic = "write-inside-atomic"
        case writeInsideNonAtomic = "write-inside-nonatomic"
        case createFileInside = "create-file-inside"
        case writeOutside = "write-outside"
        case spawn = "spawn"
        case connectLoopback = "connect-loopback"
    }

    struct Outcome {
        let allowed: Bool
        /// The POSIX errno where one surfaced. A Cocoa error carrying no underlying
        /// POSIX error is reported as its **negated** Cocoa code, so `-4`
        /// (`NSFileNoSuchFileError`) is distinguishable from `EPERM` rather than
        /// silently equal to some errno.
        let detail: Int
    }

    /// The parsed stdout of one run.
    struct Run {
        let outcomes: [Step: Outcome]
        /// The probe reached its final line. False means it was killed mid-way, which
        /// is the §6.1 failure this suite exists to rule out.
        let completed: Bool

        subscript(step: Step) -> Outcome? { outcomes[step] }
    }
}

extension SandboxDetectorMechanismMeasuredTests {

    // MARK: - The probe binary

    /// A compiled Swift binary that attempts each `Probe.Step` and reports what the
    /// policy made of it, one line per step.
    ///
    /// **Built into a deterministic temp root that is wiped on construction**, rather
    /// than a fresh directory each time. A killed-mid-run subprocess suite skips its
    /// cleanup and leaks; a fixed path bounds the leak at one binary whatever happens,
    /// which is the same reasoning behind `make clean-temp`.
    struct ProbeBinary {
        let root: URL
        let binary: URL
        let workdir: URL
        let outside: URL

        init() throws {
            // Canonicalising the root is load-bearing, not tidiness. `NSTemporaryDirectory()`
            // hands back `/var/folders/…`, a symlink to `/private/var/folders/…`, and seatbelt
            // matches a `(literal …)` against the CANONICAL path. An uncanonical path makes the
            // profile's own allow miss the probe, the exec is denied, and the run comes back
            // empty — which reads exactly like a sandbox that denied everything.
            //
            // **`resolvingSymlinksInPath()` is the wrong tool and was tried first.** Foundation
            // special-cases the `/private` prefix and STRIPS it, so it produces exactly the
            // spelling seatbelt will not match. `realpath(3)` goes the other way, and it needs
            // the directory to exist — hence the create-then-canonicalise order below.
            let base = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("swiftinfer-sandbox-probe", isDirectory: true)
            try? FileManager.default.removeItem(at: base)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

            root = URL(fileURLWithPath: Self.canonicalPath(base.path), isDirectory: true)
            binary = root.appendingPathComponent("probe")
            workdir = root.appendingPathComponent("workdir", isDirectory: true)
            outside = root.appendingPathComponent("outside", isDirectory: true)

            let source = root.appendingPathComponent("probe.swift")
            try Self.probeSource.write(to: source, atomically: true, encoding: .utf8)

            let compile = try Self.execute(
                "/usr/bin/xcrun",
                ["swiftc", source.path, "-o", binary.path]
            )
            guard FileManager.default.fileExists(atPath: binary.path) else {
                throw ProbeError.compilationFailed(compile)
            }
        }

        /// Deny every class the arm cares about. `process-exec` is denied *after* the
        /// probe's own path is allowed, because the profile applies to the exec that
        /// enters the sandbox — denying it outright makes the probe fail to launch,
        /// which reads exactly like a probe that ran and did nothing.
        var denyAllProfile: String {
            """
            (version 1)
            (allow default)
            (deny file-write*)
            (deny network*)
            (deny process-exec*)
            (allow process-exec (literal "\(binary.path)"))
            """
        }

        /// The same, plus the workdir an honest harness would grant itself.
        var allowWorkdirProfile: String {
            """
            (version 1)
            (allow default)
            (deny file-write*)
            (allow file-write* (subpath "\(workdir.path)"))
            (deny network*)
            (deny process-exec*)
            (allow process-exec (literal "\(binary.path)"))
            """
        }

        /// One run. `profile` of `nil` is the unsandboxed control.
        func run(profile: String?) throws -> Probe.Run {
            for directory in [workdir, outside] {
                try? FileManager.default.removeItem(at: directory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let output: String
            if let profile {
                let profilePath = root.appendingPathComponent("profile.sb")
                try profile.write(to: profilePath, atomically: true, encoding: .utf8)
                output = try Self.execute(
                    "/usr/bin/sandbox-exec",
                    ["-f", profilePath.path, binary.path, workdir.path, outside.path]
                )
            } else {
                output = try Self.execute(binary.path, [workdir.path, outside.path])
            }

            var outcomes: [Probe.Step: Probe.Outcome] = [:]
            for line in output.split(separator: "\n") {
                let field = line.split(separator: "|", omittingEmptySubsequences: false)
                guard field.count == 3, let step = Probe.Step(rawValue: String(field[0])) else { continue }
                outcomes[step] = Probe.Outcome(
                    allowed: field[1] == "ALLOWED",
                    detail: Int(field[2]) ?? 0
                )
            }
            // A run that parsed NO step never reached the probe's first line, so the
            // binary did not launch. Reporting that as six denials is the confident
            // zero in its most dangerous form here — it would read as a sandbox working
            // perfectly. It is a harness failure and it says so.
            guard !outcomes.isEmpty else { throw ProbeError.launchFailed(output) }

            return Probe.Run(outcomes: outcomes, completed: output.contains("PROBE COMPLETED"))
        }

        /// `realpath(3)`, which resolves `/var` → `/private/var` rather than stripping
        /// `/private` the way Foundation does. Falls back to the input on failure —
        /// the caller then fails loudly at the exec rather than here.
        static func canonicalPath(_ path: String) -> String {
            guard let resolved = realpath(path, nil) else { return path }
            defer { free(resolved) }
            return String(cString: resolved)
        }

        /// The probe, as source. Written and compiled rather than kept as a fixture
        /// target: it must be a **separate process** to be sandboxed at all, and a
        /// fixture executable in `Package.swift` would ship in every build of a package
        /// whose whole point is that it reads code and runs nothing.
        ///
        /// `ECONNREFUSED` is reported as ALLOWED on purpose — the policy permitted the
        /// `connect` and nothing was listening on port 1. Only `EPERM` is a denial, and
        /// that distinction is the entire reason a loopback address can stand in for
        /// the outbound request the first spike made.
        static let probeSource = """
        import Foundation
        #if canImport(Darwin)
        import Darwin
        #endif

        let workdir = CommandLine.arguments[1]
        let outside = CommandLine.arguments[2]

        func posixDetail(_ error: Error) -> Int {
            let wrapped = error as NSError
            if let under = wrapped.userInfo[NSUnderlyingErrorKey] as? NSError,
               under.domain == NSPOSIXErrorDomain {
                return under.code
            }
            if wrapped.domain == NSPOSIXErrorDomain { return wrapped.code }
            return -wrapped.code
        }

        func report(_ name: String, _ body: () throws -> Void) {
            do {
                try body()
                print("\\(name)|ALLOWED|0")
            } catch {
                print("\\(name)|DENIED|\\(posixDetail(error))")
            }
        }

        report("write-inside-atomic") {
            try "x".write(toFile: workdir + "/atomic.txt", atomically: true, encoding: .utf8)
        }
        report("write-inside-nonatomic") {
            try "x".write(toFile: workdir + "/plain.txt", atomically: false, encoding: .utf8)
        }
        let created = FileManager.default.createFile(
            atPath: workdir + "/created.txt", contents: Data("x".utf8)
        )
        print("create-file-inside|\\(created ? "ALLOWED" : "DENIED")|0")
        report("write-outside") {
            try "x".write(toFile: outside + "/escape.txt", atomically: false, encoding: .utf8)
        }
        report("spawn") {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/echo")
            child.arguments = ["probe"]
            child.standardOutput = FileHandle.nullDevice
            try child.run()
            child.waitUntilExit()
        }

        let handle = socket(AF_INET, SOCK_STREAM, 0)
        if handle < 0 {
            print("connect-loopback|DENIED|\\(errno)")
        } else {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(1).bigEndian
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            let outcome = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            let code = errno
            close(handle)
            if outcome == 0 || code == ECONNREFUSED {
                print("connect-loopback|ALLOWED|\\(outcome == 0 ? 0 : Int(code))")
            } else {
                print("connect-loopback|DENIED|\\(code)")
            }
        }

        print("PROBE COMPLETED")
        """

        /// Foundation's `Process`, with stdout and stderr joined — a denial can land on
        /// either and losing one would report a silent success.
        static func execute(_ executable: String, _ arguments: [String]) throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do { try process.run() } catch { throw ProbeError.launchFailed("\(executable): \(error)") }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }
    }
}
