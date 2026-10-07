import Foundation

/// What counts as a manifest — the shared spec's amendment F, implemented word for word in
/// SwiftProjectLint.
///
/// A directory **holds a manifest** iff it contains a regular file (symlinks followed) named exactly
/// `Package.swift` whose first line matches `^\s*//\s*swift-tools-version`, a UTF-8 byte-order mark
/// allowed. So a directory named `Package.swift`, a dangling symlink, and an ordinary source file
/// that happens to be called `Package.swift` are not manifests, and make no package boundary. A
/// `Package.swift` that exists but cannot be read counts as a manifest AND as doubt: nothing says
/// what it depends on, so every nested package is in.
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

    /// A directory's `Package.swift`, as the universe reads it.
    enum ManifestFile: Equatable {
        /// Not a manifest: no regular file of that name, or one whose first line is not a
        /// tools-version comment.
        case none
        /// A manifest whose text cannot be read, or decoded as UTF-8 — a manifest, and doubt.
        case unreadable
        /// A manifest, and its text.
        case text(String)
    }

    /// `directory`'s `Package.swift`, classified.
    static func manifestFile(in directory: URL) -> ManifestFile {
        let path = directory.appendingPathComponent("Package.swift").path
        // `stat`, not `lstat`: a symlink is followed, so a dangling one is not a manifest, and a
        // link to a directory is not one either. A FIFO or a device is never opened.
        var status = stat()
        guard stat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else { return .none }
        guard let data = FileManager.default.contents(atPath: path) else { return .unreadable }
        guard isToolsVersionLine(firstLineOf: data) else { return .none }
        return String(data: data, encoding: .utf8).map(ManifestFile.text) ?? .unreadable
    }

    /// Whether `directory` holds a manifest — readable or not.
    public static func holdsManifest(_ directory: URL) -> Bool {
        manifestFile(in: directory) != .none
    }

    /// The text of the manifest in the root-relative `directory` (`""` is the root), or `nil` when
    /// it cannot be read or decoded — which, for a manifest the closure reached, is doubt.
    static func manifestText(of directory: String, under root: URL) -> String? {
        let location = directory.isEmpty ? root : root.appendingPathComponent(directory)
        guard case let .text(text) = manifestFile(in: location) else { return nil }
        return text
    }

    /// Whether the first line of `data` matches `^\s*//\s*swift-tools-version`, after an optional
    /// UTF-8 byte-order mark. The line ends at the first `\n` or `\r`.
    static func isToolsVersionLine(firstLineOf data: Data) -> Bool {
        var bytes = data.prefix { $0 != 0x0A && $0 != 0x0D }
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        var line = Substring(String(decoding: bytes, as: UTF8.self))
        line = line.drop { $0.isWhitespace }
        guard line.hasPrefix("//") else { return false }
        return line.dropFirst(2).drop { $0.isWhitespace }.hasPrefix("swift-tools-version")
    }
}
