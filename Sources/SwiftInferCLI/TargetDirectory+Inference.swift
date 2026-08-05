import ArgumentParser
import Foundation

/// Working out what to scan when the caller said nothing — the asymmetry that made
/// the documented lint→infer hop fail on a reader's first attempt.
///
/// ## The friction
///
/// SwiftProjectLint takes a **repository path** and works the layout out for itself.
/// `swift-infer discover` required exactly one of `--target` / `--sources` and errored
/// without one. So piping a manifest from the first into the second — *the entire
/// documented link between the two tools* — hit an argument error before it did any
/// work. `scripts/toolchain.sh` papers over it by inferring scope before stage 0,
/// which is the workaround this replaces.
///
/// ## Why this is not a silent default
///
/// `resolveScan` refuses to guess, deliberately, on the no-confident-zero rule: a
/// tool that scans a third of a package and reports 6 suggestions is worse than one
/// that reports an error, because the reader believes it.
///
/// That rule is kept. Inference here fires **only where the layout is unambiguous**,
/// and the one genuinely ambiguous case is still a loud error:
///
/// | layout | inferred | why |
/// |---|---|---|
/// | exactly one directory under `Sources/` | that target | no other module exists to mean |
/// | several under `Sources/` | the whole tree | scanning everything cannot be a *narrower* wrong answer |
/// | no `Sources/` at all | **error naming `--sources`** | an Xcode app; guessing here is exactly the confident zero |
///
/// The middle row is the load-bearing one. Picking *a* target when several exist
/// would silently scan a fraction of the package — so it scans all of it instead,
/// which is what `--sources Sources` already means and cannot under-report.
///
/// ## It reports what it inferred
///
/// Every inference returns a note the caller prints. Silently choosing a scope is
/// how a reader ends up believing a number that answered a different question, which
/// this repo has now recorded three times in other guises.
///
/// Scoped to `discover` on purpose: that is where the hop's friction is. The other
/// five scanning commands keep the loud error, because none of them is the second
/// half of a documented two-tool pipeline.
extension TargetDirectory {

    /// A resolved scan directory plus what the caller should tell the user.
    struct InferredScan {
        let directory: URL
        /// `nil` when the caller was explicit — nothing to report.
        let note: String?
    }

    /// `resolveScan`, but inferring the scope when neither flag is given.
    static func resolveScanInferring(
        target: String?,
        sources: String?,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> InferredScan {
        guard target == nil, sources == nil else {
            // Explicit, or an explicit conflict — `resolveScan` owns both, including the
            // both-given error, so the two paths cannot drift on what "explicit" means.
            return InferredScan(
                directory: try resolveScan(target: target, sources: sources),
                note: nil
            )
        }
        let sourcesRoot = workingDirectory.appendingPathComponent("Sources")
        guard directoryExists(sourcesRoot) else {
            throw ValidationError(
                "no `Sources/` here, so there is no layout to infer. Pass --sources <directory> "
                    + "naming where your `.swift` files live — that is the Xcode-project case, and "
                    + "guessing it wrong would report a confident zero rather than an error."
            )
        }
        let modules = moduleDirectories(under: sourcesRoot)
        if modules.count == 1, let only = modules.first {
            // Resolved against the passed `workingDirectory`, NOT via `resolve(_:)` — that one
            // applies `Sources/<target>` to the PROCESS working directory, so an injected root
            // was silently ignored. In production the two coincide and it worked by accident;
            // the first test to pass a root of its own caught it.
            return InferredScan(
                directory: try resolveSources(sourcesRoot.appendingPathComponent(only).path),
                note: "no --target/--sources given; inferred --target \(only) "
                    + "(the only module under Sources/)"
            )
        }
        return InferredScan(
            directory: try resolveSources(sourcesRoot.path),
            note: "no --target/--sources given; scanning all of Sources/ "
                + "(\(modules.count) modules — naming one would scan a fraction of the package)"
        )
    }

    private static func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    /// Immediate subdirectories of `Sources/`, sorted so inference is reproducible.
    static func moduleDirectories(under sourcesRoot: URL) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: sourcesRoot, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? []
        return contents
            .filter { directoryExists($0) }
            .map(\.lastPathComponent)
            .sorted()
    }
}
