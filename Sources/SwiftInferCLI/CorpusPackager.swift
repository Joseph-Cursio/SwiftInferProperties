import Foundation

/// Cycle 113 — wraps a set of reducer sources into a standalone,
/// module-named SwiftPM package so `verify-interaction` can build + run a
/// measured survey over them. This is the "CLI corpus packaging" step the
/// A1 `.likely → .strong` campaign was waiting on: the discovery corpora
/// are loose `Sources/<Module>/` directories with no manifest, but the
/// interaction verify path synthesizes a workdir that references the user
/// corpus as a **path dependency** — which requires the corpus to be a
/// buildable package that exposes its module as a library product.
///
/// **Two invariants this enforces, both load-bearing:**
///   - The package-root directory is named after the module. SwiftPM
///     derives a path-dependency's package identity from the directory's
///     last path component (not the manifest `name:`), and the
///     synthesized verifier references the corpus by module name — a
///     mismatched root dir fails with "unknown package '<module>'".
///     (The same wrinkle the cycle-110 integration test hit.)
///   - The manifest exposes a `library(name: <module>, targets: [<module>])`
///     product, so the workdir's path dependency can resolve a product to
///     link against.
///
/// Self-contained corpora only (no external dependencies) — the verify-
/// ready idempotence corpus is dependency-free. A future extension can
/// thread `dependencies:` through for the TCA corpora.
public enum CorpusPackager {

    /// One source file destined for the packaged module's `Sources/<module>/`.
    public struct SourceFile: Equatable, Sendable {
        public let name: String
        public let contents: String

        public init(name: String, contents: String) {
            self.name = name
            self.contents = contents
        }
    }

    public enum PackagerError: Error, CustomStringConvertible, Equatable {
        case emptyModuleName
        case noSourceFiles

        public var description: String {
            switch self {
            case .emptyModuleName:
                return "CorpusPackager: module name must be non-empty "
                    + "(it names the package root directory + the library product)."

            case .noSourceFiles:
                return "CorpusPackager: at least one source file is required."
            }
        }
    }

    /// The default SwiftPM tools version stamped into the manifest — matches
    /// the cycle-110 verifier-workdir/IDemo proof package.
    public static let defaultToolsVersion = "6.1"

    /// Scaffold a standalone package at `<destinationParent>/<moduleName>/`
    /// and return its root URL. Overwrites an existing `Package.swift` /
    /// source files at that location (idempotent re-packaging).
    @discardableResult
    public static func package(
        moduleName: String,
        sourceFiles: [SourceFile],
        into destinationParent: URL,
        toolsVersion: String = defaultToolsVersion
    ) throws -> URL {
        guard !moduleName.isEmpty else { throw PackagerError.emptyModuleName }
        guard !sourceFiles.isEmpty else { throw PackagerError.noSourceFiles }

        let root = destinationParent.appendingPathComponent(moduleName)
        let sourcesDir = root
            .appendingPathComponent("Sources")
            .appendingPathComponent(moduleName)
        try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)

        try Data(manifestSource(moduleName: moduleName, toolsVersion: toolsVersion).utf8)
            .write(to: root.appendingPathComponent("Package.swift"))
        for file in sourceFiles {
            try Data(file.contents.utf8)
                .write(to: sourcesDir.appendingPathComponent(file.name))
        }
        return root
    }

    /// Convenience: read every top-level `.swift` file from
    /// `sourcesDirectory` (a loose corpus `Sources/<Module>/` directory)
    /// and package them. Non-recursive and `.swift`-only by design —
    /// corpora keep one flat reducer-per-file layout; nested asset / plist
    /// directories (the TCA corpora carry these) are skipped, not copied.
    @discardableResult
    public static func package(
        moduleName: String,
        fromSourcesDirectory sourcesDirectory: URL,
        into destinationParent: URL,
        toolsVersion: String = defaultToolsVersion
    ) throws -> URL {
        try package(
            moduleName: moduleName,
            sourceFiles: readSwiftSources(in: sourcesDirectory),
            into: destinationParent,
            toolsVersion: toolsVersion
        )
    }

    /// Top-level `.swift` files in `directory`, sorted by name for a
    /// deterministic package layout.
    static func readSwiftSources(in directory: URL) throws -> [SourceFile] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return try entries
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                SourceFile(
                    name: url.lastPathComponent,
                    contents: try String(contentsOf: url, encoding: .utf8)
                )
            }
    }

    /// The generated `Package.swift` — a single dependency-free library
    /// target. Kept as a string template (not a `PackageDescription`
    /// build) because this writes a manifest for a *separate* package.
    static func manifestSource(moduleName: String, toolsVersion: String) -> String {
        """
        // swift-tools-version: \(toolsVersion)
        import PackageDescription

        let package = Package(
            name: "\(moduleName)",
            platforms: [.macOS(.v14)],
            products: [.library(name: "\(moduleName)", targets: ["\(moduleName)"])],
            targets: [.target(name: "\(moduleName)")]
        )
        """
    }

    /// M3 — package several modules into ONE SwiftPM package, one dependency-
    /// free library product per module (product name == module name), so
    /// `verify-interaction` can resolve + build each module's product
    /// independently for multi-module measured verify. Each module's top-level
    /// `.swift` files become `Sources/<module>/`. The root dir is named
    /// `packageName` (the resolver derives package identity from the basename);
    /// product names match module names so
    /// `PackageProductResolver.libraryProduct(exposingModule:)` picks each.
    @discardableResult
    public static func packageMultiModule(
        packageName: String,
        modules: [(name: String, sourcesDirectory: URL)],
        into destinationParent: URL,
        toolsVersion: String = defaultToolsVersion
    ) throws -> URL {
        guard !packageName.isEmpty else { throw PackagerError.emptyModuleName }
        guard !modules.isEmpty else { throw PackagerError.noSourceFiles }

        let root = destinationParent.appendingPathComponent(packageName)
        for module in modules {
            guard !module.name.isEmpty else { throw PackagerError.emptyModuleName }
            let sourcesDir = root
                .appendingPathComponent("Sources")
                .appendingPathComponent(module.name)
            try FileManager.default.createDirectory(at: sourcesDir, withIntermediateDirectories: true)
            for file in try readSwiftSources(in: module.sourcesDirectory) {
                try Data(file.contents.utf8)
                    .write(to: sourcesDir.appendingPathComponent(file.name))
            }
        }
        try Data(multiModuleManifestSource(
            packageName: packageName,
            moduleNames: modules.map(\.name),
            toolsVersion: toolsVersion
        ).utf8).write(to: root.appendingPathComponent("Package.swift"))
        return root
    }

    /// The generated `Package.swift` for a multi-module corpus — one library
    /// product + target per module (product name == module name).
    static func multiModuleManifestSource(
        packageName: String,
        moduleNames: [String],
        toolsVersion: String
    ) -> String {
        let products = moduleNames
            .map { ".library(name: \"\($0)\", targets: [\"\($0)\"])" }
            .joined(separator: ",\n            ")
        let targets = moduleNames
            .map { ".target(name: \"\($0)\")" }
            .joined(separator: ",\n            ")
        return """
        // swift-tools-version: \(toolsVersion)
        import PackageDescription

        let package = Package(
            name: "\(packageName)",
            platforms: [.macOS(.v14)],
            products: [
                \(products)
            ],
            targets: [
                \(targets)
            ]
        )
        """
    }
}
