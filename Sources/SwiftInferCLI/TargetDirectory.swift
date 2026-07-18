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
            throw ValidationError(
                "no target `\(target)` — nothing at "
                    + "\(directory.absoluteURL.standardizedFileURL.path).\(availableTargetsClause(in: sources))"
            )
        }

        return directory
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

    // MARK: - Private

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }

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
