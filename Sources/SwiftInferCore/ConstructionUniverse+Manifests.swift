import Foundation

/// What counts as a manifest — the shared spec's amendment F, implemented word for word in
/// SwiftProjectLint (`ConstructionUniverse+Manifest.swift` there, with the same names).
///
/// A directory **holds a manifest** iff it contains a regular file (symlinks followed) named exactly
/// `Package.swift` whose first line matches `^\s*//\s*swift-tools-version`, a UTF-8 byte-order mark
/// allowed. So a directory named `Package.swift`, a dangling symlink, and an ordinary source file
/// that happens to be called `Package.swift` are not manifests, and make no package boundary. A
/// `Package.swift` that exists but cannot be read as UTF-8 text counts as a manifest AND as doubt:
/// nothing says what it depends on, so every nested package is in.
///
/// Why the first line: it is what SwiftPM itself requires of a manifest, and the cheapest test that
/// tells one from a source file. Before it, `Sources/App/Models/Package.swift` — a `struct Package`
/// inside the `App` target — made `Models/` a nested package the root never names, and the bound
/// dropped every other file the target compiles there. A dangling `Ghost/Package.swift` made
/// `Ghost/` a package whose unreadable manifest was doubt, so an unrelated `Demo/` came back in.
///
/// One test for every place the universe asks: the root search, the root's own manifest, the walk's
/// nested packages, and the closure's reads by path.
extension ConstructionUniverse {

    /// What a directory holds at `Package.swift`.
    public enum Manifest: Equatable, Sendable {
        /// No manifest: nothing of that name, or a directory, a dangling link, or a file whose first
        /// line is not a tools-version comment.
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

    /// The text of the manifest in the root-relative `directory` (`""` is the root), or `nil` when
    /// it cannot be read — which, for a manifest the closure reached, is doubt.
    static func manifestText(of directory: String, under root: URL) -> String? {
        let location = directory.isEmpty ? root : root.appendingPathComponent(directory)
        guard case let .text(text) = manifest(inDirectory: location) else { return nil }
        return text
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

    /// Whether `text` begins as a manifest does: a first line matching
    /// `^\s*//\s*swift-tools-version`, after an optional UTF-8 byte-order mark.
    public static func isManifest(_ text: String) -> Bool {
        var firstLine = text.prefix { $0 != "\n" && $0 != "\r\n" }
        if firstLine.first == "\u{FEFF}" { firstLine = firstLine.dropFirst() }
        return firstLine.prefixMatch(of: #/\s*//\s*swift-tools-version/#) != nil
    }
}
