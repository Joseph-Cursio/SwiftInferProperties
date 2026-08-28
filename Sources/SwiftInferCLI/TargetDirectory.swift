import ArgumentParser
import Foundation
import SwiftInferCore

/// Resolves `--target` to the directory it names, and **fails when that directory is not there**.
///
/// Every command used to do this inline:
///
///     let directory = URL(fileURLWithPath: "Sources").appendingPathComponent(target)
///
/// with no check that anything existed at the other end. The scanner returns `[]` for a directory
/// it cannot enumerate, so a target that does not exist scanned nothing, found nothing, printed
/// `0 suggestions.` and **exited 0**:
///
///     $ swift-infer discover --target ThisDoesNotExist
///     0 suggestions.
///     $ echo $?
///     0
///
/// A confident, successful-looking zero is the worst answer a tool can give, because the reader
/// believes it. And it is not an exotic case: `--target` resolves under `Sources/`, so this is how
/// *every user of an Xcode project* meets the tool — an app has no `Sources/` directory, so the
/// first thing they are told is that their code has no properties, by a tool that never opened a
/// file.
enum TargetDirectory {

    /// The directory `--target` names, or a `ValidationError` naming the path that was looked for.
    ///
    /// The error lists the targets that *do* exist. A reader who mistypes a target, or who is in
    /// the wrong directory, or who is pointing an Xcode project at a SwiftPM-shaped flag, needs to
    /// know which of those happened — and the answer is usually obvious the moment they see the
    /// list.
    /// - Parameters:
    ///   - target: the SwiftPM target name.
    ///   - root: the package root to resolve against. Defaults to the process working directory,
    ///     which is what `--target`'s documented "relative to the working directory" means; taking
    ///     it as a parameter keeps the resolution a function of its inputs rather than of global
    ///     process state, which is also the only way to test it without two suites fighting over
    ///     `chdir`.
    static func resolve(
        _ target: String,
        relativeTo root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> URL {
        let sources = root.appendingPathComponent("Sources")
        let directory = sources.appendingPathComponent(target)

        guard isDirectory(sources) else {
            throw ValidationError(
                "no `Sources/` directory at \(sources.absoluteURL.standardizedFileURL.path). "
                    + "`--target` names a SwiftPM target and resolves to `Sources/<target>/`, so it "
                    + "needs a package laid out that way. Run this from the package root — or, if "
                    + "this is an Xcode project rather than a SwiftPM package, there is no "
                    + "`Sources/` to find and `--target` cannot reach your code."
            )
        }

        guard isDirectory(directory) else {
            // `Sources/<target>/` is a CONVENTION, not a rule — a manifest may put a target
            // anywhere via `path:`. Ask the manifest before concluding the target is absent.
            //
            // Third recurrence of this trap in a third subsystem, which is why the fallback is
            // here rather than at the call sites: `scripts/measurement.py` paid for it when GRDB
            // (`path: "GRDB"`) resolved to zero files, and `VerifyTargetInference.manifestModule`
            // paid for it when swift-system (`path: "Sources/System"` for target `SystemPackage`)
            // reported 21 module-resolution failures under a carrier label. `index --target` never
            // learned it, so `Euclid` — whose manifest says `path: "Sources"` — was unreachable.
            //
            // The convention is tried FIRST and this only runs when it misses, so no package that
            // resolved before resolves differently now. Confirmed on disk before being returned,
            // for `manifestModule`'s stated reason: a name taken from a manifest is a guess until
            // something on disk agrees with it.
            if let declared = manifestDirectory(for: target, packageRoot: root) {
                return declared
            }
            throw ValidationError(
                "no target `\(target)` — nothing at "
                    + "\(directory.absoluteURL.standardizedFileURL.path).\(availableTargetsClause(in: sources))"
            )
        }

        return directory
    }

    /// The directory a manifest declares for `target` via `path:`, when it exists on disk.
    ///
    /// Nil — never a guess — when the manifest cannot be read, names no such target, or names a
    /// directory that is not there. Each of those leaves the caller reporting the same
    /// target-not-found error it reported before, which is the behaviour this fallback extends
    /// rather than replaces.
    static func manifestDirectory(for target: String, packageRoot: URL) -> URL? {
        for declared in TargetIsolation.declaredTargetDirectories(packageRoot: packageRoot)
        where declared.name == target {
            let directory = packageRoot
                .appendingPathComponent(declared.path)
                .standardizedFileURL
            if isDirectory(directory) { return directory }
        }
        return nil
    }

    /// Resolves an explicit `--sources <dir>`: the directory is scanned **as given**, with no
    /// `Sources/<target>/` convention applied.
    ///
    /// This is the Xcode escape hatch (C1). `--target` resolves under `Sources/`, which an app does
    /// not have — so an Xcode user's first meeting with the tool was an error telling them their code
    /// was unreachable. `--sources` points swift-infer straight at a source directory instead, which
    /// is what "aim it at the `.xcodeproj` tree" means in practice: pass the folder your `.swift`
    /// files live in. Fails loudly, naming the path, when the directory is not there — the same
    /// no-silent-zero discipline `resolve(_:)` enforces for `--target`.
    static func resolveSources(
        _ path: String,
        relativeTo root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> URL {
        // `appendingPathComponent` for the relative case, not `URL(fileURLWithPath:relativeTo:)`: the
        // latter resolves a relative path against `root`'s *last component* when `root` carries no
        // trailing slash, silently making the directory a sibling rather than a child. An absolute
        // `--sources` path is taken as-is.
        let directory = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : root.appendingPathComponent(path)

        guard isDirectory(directory) else {
            throw ValidationError(
                "no directory at \(directory.absoluteURL.standardizedFileURL.path). `--sources` "
                    + "names a source directory to scan directly — the Xcode escape hatch for a "
                    + "project that has no `Sources/<target>/` layout. Point it at the folder your "
                    + "`.swift` files live in."
            )
        }

        return directory
    }

    /// One directory to scan, with the label the caller should use for it.
    ///
    /// Discovery works on **directories**; only the label needs to know where it came from. For
    /// `--target Foo` the label is `Foo` (the module name, which multi-module tagging and pins
    /// depend on); for `--sources path/to/dir` it is the directory's last path component, which is
    /// the closest honest stand-in — an Xcode project has no module name to read.
    struct ScanRoot: Equatable {
        let label: String
        let directory: URL
    }

    /// Resolves exactly one of `--target` / `--sources` to a directory.
    ///
    /// Both given is ambiguous; neither leaves nothing to scan. Both are loud errors rather than a
    /// silent default — the same no-confident-zero discipline `resolve(_:)` enforces.
    static func resolveScan(target: String?, sources: String?) throws -> URL {
        switch (target, sources) {
        case let (targetName?, nil):
            return try resolve(targetName)

        case let (nil, sourcesPath?):
            return try resolveSources(sourcesPath)

        case (nil, nil):
            throw ValidationError(
                "pass exactly one of --target <SwiftPM target> or --sources <directory>. For an "
                    + "Xcode project — which has no `Sources/<target>/` layout — use --sources and "
                    + "point it at the folder your `.swift` files live in."
            )

        case (.some, .some):
            throw ValidationError(
                "--target and --sources are mutually exclusive: --target applies the "
                    + "`Sources/<target>/` convention, --sources scans a directory as given. Pass "
                    + "one."
            )
        }
    }

    /// The repeatable form, for commands that survey several modules in one run.
    ///
    /// Mixing the two is allowed and useful: a workspace can hold a SwiftPM package *and* an app
    /// target, and there is no reason a survey should have to choose. Order is targets then
    /// sources, so a single-`--target` run is byte-identical to what it was before this existed.
    static func resolveScanRoots(
        targets: [String],
        sources: [String],
        relativeTo root: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) throws -> [ScanRoot] {
        guard !targets.isEmpty || !sources.isEmpty else {
            throw ValidationError(
                "pass at least one of --target <SwiftPM target> or --sources <directory>. For an "
                    + "Xcode project — which has no `Sources/<target>/` layout — use --sources and "
                    + "point it at the folder your `.swift` files live in."
            )
        }
        let fromTargets = try targets.map {
            ScanRoot(label: $0, directory: try resolve($0, relativeTo: root))
        }
        let fromSources = try sources.map { path -> ScanRoot in
            let directory = try resolveSources(path, relativeTo: root)
            return ScanRoot(
                label: directory.standardizedFileURL.lastPathComponent,
                directory: directory
            )
        }
        return fromTargets + fromSources
    }

    /// Warns when the target holds no Swift files at all, so a run over an empty corpus cannot be
    /// mistaken for a run that found nothing in your code.
    ///
    /// **Only the empty case speaks.** A `scanned N file(s) in <path>` line on every run was the
    /// obvious thing to add, and it is wrong: stderr is a byte-stable contract here (PRD §16 #6,
    /// byte-identical reproducibility), and an absolute path differs from machine to machine, so
    /// printing one unconditionally would make identical inputs produce different output. The
    /// existing diagnostic tests caught it, which is what they are for.
    ///
    /// The silence is safe now because the two ways a zero could lie have both been closed: a
    /// target that does not exist is an error, and a target with nothing in it warns. What is left
    /// — a populated target that genuinely yields no suggestions — is a zero worth believing.
    static func warnIfEmpty(_ directory: URL, to diagnostics: any DiagnosticOutput) {
        guard SwiftSourceFiles.sorted(in: directory).isEmpty else { return }

        diagnostics.writeDiagnostic(
            "warning: scanned 0 Swift files in "
                + "\(directory.absoluteURL.standardizedFileURL.path) — the directory exists but "
                + "holds no `.swift` files, so anything this run reports is a statement about an "
                + "empty corpus, not about your code."
        )
    }

    /// Does `url` name a directory that actually exists?
    ///
    /// Internal rather than private because `VerifyTargetInference` walks this mapping in the
    /// other direction — path back to module — and applies the same "confirm the directory is
    /// really there" rule. Sharing the check is what keeps that one rule, rather than two copies
    /// of it that can drift apart in separate files.
    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

    // MARK: - Private

    /// " Available targets: A, B, C." — or a note that there are none.
    private static func availableTargetsClause(in sources: URL) -> String {
        let available = (try? FileManager.default.contentsOfDirectory(
            at: sources,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?
            .filter { isDirectory($0) }
            .map(\.lastPathComponent)
            .sorted() ?? []

        guard !available.isEmpty else {
            return " `Sources/` exists but contains no target directories."
        }
        return " Available target(s): \(available.joined(separator: ", "))."
    }
}
