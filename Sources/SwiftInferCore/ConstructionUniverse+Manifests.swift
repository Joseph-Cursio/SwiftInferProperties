import Foundation

/// What counts as a manifest — the shared spec's amendments F and S, implemented word for word in
/// SwiftProjectLint (`ConstructionUniverse+Manifest.swift` there, with the same names).
///
/// A directory **holds a manifest** iff it contains a regular file (symlinks followed) named exactly
/// `Package.swift` whose text SwiftPM would load as one (`isManifest(_:)`, amendment S): its first
/// non-blank line is a `// swift-tools-version` comment, the label in any case, or — from tools
/// version 6.0, which accepts the comment after other lines — some later line is one naming a major
/// version of 6 or more. So a directory named `Package.swift`, a dangling symlink, and an ordinary
/// source file that happens to be called `Package.swift` are not manifests, and make no package
/// boundary. A `Package.swift` that exists but cannot be read as UTF-8 text counts as a manifest AND
/// as doubt: nothing says what it depends on, so every nested package is in.
///
/// Why the tools-version comment: SwiftPM itself requires it, and it is the cheapest test that
/// tells a manifest from a source file. Amendment F first read it on the first line only, and
/// case-sensitively; SwiftPM 6.4 loads leading empty lines (and from 5.4 lines of whitespace),
/// `// SWIFT-TOOLS-VERSION:5.9`, Unicode spacing such as `//\u{00A0}swift-tools-version`, and at 6.0
/// or later a copyright header above the comment — and F's reading dropped such a package's
/// closure, or unbounded a root (amendments S and S′). Before either rule,
/// `Sources/App/Models/Package.swift` — a `struct Package` inside the `App` target — made
/// `Models/` a nested package the root never names, and the bound
/// dropped every other file the target compiles there. A dangling `Ghost/Package.swift` made
/// `Ghost/` a package whose unreadable manifest was doubt, so an unrelated `Demo/` came back in.
///
/// One test for every place the universe asks: the root search, the root's own manifest, the walk's
/// nested packages, and the closure's reads by path.
extension ConstructionUniverse {

    /// What a directory holds at `Package.swift`.
    public enum Manifest: Equatable, Sendable {
        /// No manifest: nothing of that name, or a directory, a dangling link, or a file SwiftPM
        /// would not load as one (`isManifest(_:)`).
        case absent
        /// A manifest, and its text.
        case text(String)
        /// A regular file of that name that cannot be read as UTF-8 text: a manifest, and doubt.
        case unreadable
    }

    /// What `directory` holds at `Package.swift`.
    public static func manifest(inDirectory directory: URL) -> Manifest {
        manifest(atPath: directory.appendingPathComponent("Package.swift").path)
    }

    /// The file at `path`, read as a manifest.
    static func manifest(atPath path: String) -> Manifest {
        // `stat`, not `lstat`: a symlink is followed, so a dangling one is not a manifest, and a
        // link to a directory is not one either. A FIFO or a device is never opened.
        var status = stat()
        guard stat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return .absent }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return .unreadable }
        return isManifest(text) ? .text(text) : .absent
    }

    /// Whether `directory` holds a manifest — readable or not.
    public static func holdsManifest(_ directory: URL) -> Bool {
        manifest(inDirectory: directory) != .absent
    }

    /// Every manifest `directory` holds: its `Package.swift`, then each `Package@swift-*.swift`
    /// beside it in name order, each read as `manifest(inDirectory:)` reads one (amendment O) —
    /// whatever `Package.swift` is, as SwiftProjectLint reads them. Whether the directory IS a
    /// package is decided by `Package.swift` alone (`holdsManifest(_:)`).
    ///
    /// The bound takes the **union** of their dependencies. SwiftPM builds a package with whichever
    /// one the toolchain selects, and nothing cheap says which: a root whose `Package.swift` names no
    /// dependency and whose `Package@swift-6.0.swift` names `Packages/A` compiles `A` on every
    /// toolchain this tool runs on, yet reading `Package.swift` alone left `A` out.
    public static func manifests(inDirectory directory: URL) -> [Manifest] {
        [manifest(inDirectory: directory)] + versionSpecificManifestNames(in: directory).map {
            manifest(atPath: directory.appendingPathComponent($0).path)
        }
    }

    /// The files whose edit can change what `directory`'s manifests say: its `Package.swift` and
    /// every `Package@swift-*.swift` beside it.
    static func manifestURLs(inDirectory directory: URL) -> [URL] {
        (["Package.swift"] + versionSpecificManifestNames(in: directory)).map(directory.appendingPathComponent)
    }

    /// `Package@swift-*.swift` entries directly in `directory`, sorted.
    static func versionSpecificManifestNames(in directory: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasPrefix("Package@swift-") && $0.hasSuffix(".swift") }.sorted()
    }

    /// Whether `directory` holds an `*.xcodeproj` or `*.xcworkspace` as a direct child — the shared
    /// spec's amendment G. An Xcode project beside a root manifest may compile local packages the
    /// manifest never names (an app target's `XCLocalSwiftPackageReference`, a workspace's
    /// `group:` reference), so such a root bounds nothing: every nested package is in. Reading the
    /// project file instead would need its own doubt rule, since pre-Xcode-15 projects and
    /// workspaces reference local packages as plain folder references. A direct child only: the
    /// workspace SwiftPM keeps for a package lives under `.swiftpm/`, and is no evidence of
    /// another build.
    static func holdsXcodeProject(_ directory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    /// Whether SwiftPM would load `text` as a manifest — the shared spec's amendments S and S′, the
    /// reference implementation verbatim, with the shared cases file's `isManifest` section as its
    /// arbiter. After one leading U+FEFF, split into lines on `Character.isNewline` (`\n`, `\r\n`,
    /// a lone `\r`):
    ///
    /// - (a) the first line holding anything but whitespace matches
    ///   `^\h*//\h*swift-tools-version`, the label case-insensitive (`///` does not), at any
    ///   version; or
    /// - (b) some later line matches `^\h*//\h*swift-tools-version\h*:\h*([0-9]+)` with a major
    ///   version of 6 or more — tools version 6.0 accepts the comment after other lines.
    ///
    /// `\h` is horizontal whitespace, as SwiftPM's own parser reads spacing (`Character.isWhitespace`):
    /// `//\u{00A0}swift-tools-version` loads, and amendment S's `[ \t]` refused it (S′). A cheap
    /// label check runs before rule (b)'s regex, which costs ~50 µs a line: a long source file named
    /// `Package.swift` is read in milliseconds, not seconds.
    ///
    /// Accepted: rule (a) skips blank lines at every version, but only truly EMPTY lines load at
    /// every version — a line of whitespace, a CRLF blank line among them, is rejected below 5.4, and
    /// such a package cannot build anyway; and a `// swift-tools-version:6…` line inside a string
    /// literal below the first line — a code generator's template in `Sources/Gen/Package.swift` —
    /// makes that file a manifest.
    public static func isManifest(_ text: String) -> Bool {
        var body = Substring(text)
        if body.first == "\u{FEFF}" { body = body.dropFirst() }
        let lines = body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard let first = lines.firstIndex(where: { !$0.allSatisfy(\.isWhitespace) }) else { return false }
        if lines[first].prefixMatch(of: #/\h*//\h*(?i:swift-tools-version)/#) != nil { return true }
        return lines[lines.index(after: first)...].contains { line in
            // Only a line that names the label can match; skip the regex, which costs far more, for the rest.
            let marker = line.drop(while: \.isWhitespace)
            guard marker.hasPrefix("//"),
                  marker.dropFirst(2).drop(while: \.isWhitespace).prefix(19).lowercased() == "swift-tools-version"
            else { return false }
            guard let match = line.prefixMatch(of: #/\h*//\h*(?i:swift-tools-version)\h*:\h*([0-9]+)/#) else {
                return false
            }
            return (Int(match.1) ?? 0) >= 6
        }
    }
}
