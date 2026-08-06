import Foundation
import SwiftInferCore

/// One SwiftPM package holding **every** stub in a survey as its own executable
/// target, instead of one throwaway package per suggestion.
///
/// ## Why
///
/// Measured on `fixtures/cycle27-surface` — 53 entries, four real library
/// dependencies: the per-suggestion design costs **13m 30s and 24 GB**, of which
/// essentially all is rebuilding the same four dependencies 53 times. Each workdir
/// is **464 MB** (24 GB / 53); the input that differs between them is a 113-line
/// `main.swift`. The shared package produces the same 53 verdicts in **100s and
/// 1.6 GB cold**, **45s warm**.
///
/// **Cold and warm are both stated because the first draft of this comment was not.**
/// It read `54s`, the docs read `103s`, and neither said which cache state it was
/// taken in — so they looked like a contradiction for a day. Re-measured 2026-08-05,
/// one binary, back to back: **cold** (no `verify-workdir`) 100s / 1596 MB, **warm**
/// (reusing that `.build`) 45s / 1596 MB. Both figures were right. A wall-clock
/// number without its cache state is not a measurement.
///
/// The cost model changes from `N × (dependency build + compile + link)` to
/// `1 × dependency build + N × (compile + link)`.
///
/// ## What the per-suggestion design was actually buying
///
/// `VerifierWorkdir`'s doc gives the reason as *"concurrent verify calls against
/// different suggestions don't stomp on each other's `.build/`"*. That is real, but
/// it is one of three properties that were conflated, and only it needed a separate
/// package:
///
/// - **Run isolation** — a `predicate` law fails by **trap**, which kills the
///   process. Preserved here: every target is its own executable, run as its own
///   process, so a trap takes one law rather than the batch.
/// - **Per-entry build attribution** — `build-failed` must land on one entry, not
///   blank the run. Preserved by building **per product** (see below).
/// - **Concurrent `.build` safety** — the actual reason, and a consequence of the
///   `--max-parallel` strategy rather than of the problem. Handled by building
///   serially and running in parallel; the builds were the cost, not the runs.
///
/// ## `--product`, not `swift build`, and not `--target`
///
/// Measured with one deliberately broken stub in the package:
///
/// | command | result |
/// |---|---|
/// | `swift build` (whole package) | exit 1, **zero** binaries — one bad stub poisons all 52 good targets |
/// | `swift build --product <T>` ×53 | **52 built, 1 failed — exactly the broken one** |
///
/// So the naive single-build form genuinely does fail the way the per-suggestion
/// design implicitly guarded against. Building per product against the
/// already-built shared dependency graph keeps attribution intact.
///
/// **`--target` is the wrong flag and lies**: it returns exit 0 and produces only an
/// entitlement plist, no binary. An implementation keying on it would report
/// "built" for something that does not exist.
enum SharedVerifierPackage {

    /// A stub that composed successfully and wants a target.
    struct Member {
        let entry: SemanticIndexEntry
        let stubSource: String
        let userPackage: VerifierWorkdir.UserPackageReference?
        let mode: WorkdirMode
        /// Target name, and the directory under `Sources/`. Prefixed because a
        /// SwiftPM target name must be an identifier and a hash starts with a digit;
        /// keeping the hash makes each binary traceable to its entry without a side
        /// table.
        var targetName: String { "V" + entry.identityHash.replacingOccurrences(of: "0x", with: "") }
    }

    /// Write the package. Returns its root.
    ///
    /// Every member contributes its own target dependency list, so a `.interaction`
    /// stub does not acquire `.algebraic`'s products — the per-mode narrowing the
    /// single-workdir path already applies is preserved per target rather than
    /// flattened into a union.
    static func synthesize(members: [Member], at root: URL) throws -> URL {
        try? FileManager.default.removeItem(at: root.appendingPathComponent("Sources"))
        var targetBlocks: [String] = []
        var packageDeps: Set<String> = []

        for member in members {
            try write(member: member, under: root)
            packageDeps.formUnion(packageDependencies(of: member))
            // Reuses the SAME renderer the per-suggestion path uses, rather than
            // re-deriving the product list here. Two spellings of "what does an
            // algebraic stub need" would drift, which is the failure this repo keeps
            // recording.
            let products = VerifierWorkdir.renderTargetDependenciesBlock(
                userPackage: member.userPackage, mode: member.mode
            )
            targetBlocks.append("""
                    .executableTarget(
                        name: "\(member.targetName)",
                        dependencies: [
            \(products)
                        ]
                    )
            """)
        }

        let manifest = """
        // swift-tools-version: 6.1
        // Auto-generated by SwiftInferProperties. One target per surveyed suggestion —
        // see `SharedVerifierPackage` for why this is one package and not N.
        import PackageDescription

        let package = Package(
            name: "SwiftInferVerifierSurvey",
            platforms: [
                \(platformLine(members: members))
            ],
            dependencies: [
                \(packageDeps.sorted().joined(separator: ",\n        "))
            ],
            targets: [
        \(targetBlocks.joined(separator: ",\n"))
            ]
        )
        """
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try manifest.write(
            to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8
        )
        return root
    }

    /// The survey package's platform line, mirrored from the corpora its members
    /// reference. Read rather than hardcoded for the reason
    /// `VerifierWorkdir.macOSPlatformLine` documents — a floor below the corpus
    /// fails every entry in the survey, not some of them.
    ///
    /// One package holds every member, so it must satisfy the *highest*
    /// requirement present. Members with no user package contribute nothing;
    /// with none at all this lands on `defaultMacOSVersion`, which is what the
    /// survey emitted before this existed.
    private static func platformLine(members: [Member]) -> String {
        let versions = members.compactMap { member -> String? in
            member.userPackage.flatMap {
                VerifierWorkdir.declaredMacOSVersion(inPackageAt: $0.packagePath)
            }
        }
        // Numeric max on the major component; see `declaredMacOSVersion` for why
        // string ordering is wrong here.
        let highest = versions
            .compactMap { Int($0.split(separator: ".").first.map(String.init) ?? "") }
            .max()
        let version = highest.map { "\($0).0" } ?? VerifierWorkdir.defaultMacOSVersion
        return ".macOS(\"\(version)\")"
    }

    /// One target directory holding one `main.swift` — the shape SwiftPM requires of
    /// an executable target, and the same file the per-suggestion workdir wrote.
    private static func write(member: Member, under root: URL) throws {
        let sources = root.appendingPathComponent("Sources")
            .appendingPathComponent(member.targetName)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try member.stubSource.write(
            to: sources.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8
        )
    }

    /// The `.package(…)` lines this member needs, read back off the shared renderer.
    ///
    /// Read rather than re-listed: the renderer interleaves explanatory comments with
    /// its entries, and every line that is not a `.package(` call is one of those.
    /// Keying on the prefix means a new comment cannot become a phantom dependency.
    private static func packageDependencies(of member: Member) -> Set<String> {
        let block = VerifierWorkdir.renderDependenciesBlock(
            userPackage: member.userPackage, mode: member.mode
        )
        var found: Set<String> = []
        for line in block.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            if trimmed.hasPrefix(".package(") { found.insert(trimmed) }
        }
        return found
    }
}
