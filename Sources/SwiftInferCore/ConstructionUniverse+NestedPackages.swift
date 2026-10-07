import SwiftParser
import SwiftSyntax

/// Which nested packages' files are in the construction universe: **those the root compiles** —
/// the shared spec's amendment B, implemented word for word in SwiftProjectLint too, and pinned in
/// both repos by the shared `construction-universe-cases.json`.
///
/// A *nested package* is a directory below the root (never the root itself) that holds a
/// manifest — a `Package.swift` whose first line is a tools-version comment (amendment F,
/// `ConstructionUniverse+Manifests.swift`). Every file belongs to the nearest one above it, or to
/// the root's own package when there is none; the root's own files are always in the universe,
/// and a nested package's are only when the root reaches it:
///
/// - **The root has a manifest**: the closure of its local path dependencies. Each manifest's
///   `.package(path:)` literals are resolved from that manifest's directory and followed
///   transitively. A manifest in the closure that passes `path:` anything but a string literal may
///   depend on any of them, so then **every** nested package is in (any doubt includes), and so
///   does one that exists and cannot be read. A path that leaves the root is ignored: the universe
///   never does.
/// - **It has none** — an Xcode app's folder, a workspace folder — **or an `*.xcodeproj` /
///   `*.xcworkspace` sits beside it** (amendment G): an Xcode project compiles local packages no
///   manifest names, and nothing cheap says which, so every nested package is in.
///
/// ## Why bound it
///
/// A table built from every nested package over-refutes a namesake the root never compiles. This
/// repo's own `fixtures/*/Package.swift` are packages its manifest never names, and an unrelated
/// `Demo/` package declaring a top-level `Row` that mints a `UUID` refuted the root's plain
/// `Row(n:)` — `discover --effect-annotations` stopped advising a `make(n:)` that main advised,
/// over a package the scan never judged.
extension ConstructionUniverse {

    /// The literal paths of `manifest`'s local package dependencies, in source order —
    /// `.package(path: "…")` and `.package(name: "…", path: "…")`, with or without an explicit
    /// `Package.Dependency` base — each the value the compiler sees (amendment H:
    /// `representedLiteralValue`, so escapes are processed and raw strings allowed), or `nil` when
    /// a `.package(…)` call passes `path:` something that is not a string literal without
    /// interpolation (the doubt rule).
    ///
    /// The manifest is parsed, not pattern-matched: a dependency commented out, or the text of one
    /// inside a string, is not a dependency. A `path:` belonging to anything else — a target's
    /// `.target(name:path:)` — is not one either.
    ///
    /// **The parse and the walk run on a `LargeStackWorkers` thread** (amendment K), like every
    /// other parse of universe text: both recurse as deep as the manifest nests, and the CLI runs on
    /// a ~512 KB cooperative stack. A nested package's manifest holding a 1,000-arm `else if` chain
    /// `SIGBUS`ed `discover` there — the one parse the universe's move to large stacks had missed.
    /// Here, rather than at a caller, so every caller is covered.
    public static func localPackageDependencies(manifest: String) -> [String]? {
        LargeStackWorkers.run {
            let collector = PathDependencyCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: manifest))
            return collector.isReadable ? collector.paths : nil
        }
    }

    /// The nested packages whose files are in the universe: every one of `nestedPackages` when the
    /// root has no manifest or the closure meets doubt, else the closure's nodes — which may include
    /// a package the walk never entered (amendment I), whose own files the predicate rejects.
    ///
    /// - Parameters:
    ///   - nestedPackages: root-relative directories (no trailing `/`) that hold a manifest.
    ///   - rootHasManifest: whether the root itself holds one — `false` too when an Xcode project
    ///     sits beside it (amendment G).
    ///   - rootPath: the root's absolute path, resolved; every dependency must lie under it once
    ///     resolved itself.
    ///   - resolvingSymlinks: an absolute path with every symlink resolved, by the same resolution
    ///     the root's path went through (amendment H). The identity for an in-memory tree.
    ///   - holdsManifest: whether a root-relative directory holds a manifest ON DISK — the closure
    ///     follows each dependency to `<dir>/Package.swift` by path (amendment I), so a package
    ///     under `Tests/`, a hidden or a pruned directory still passes its dependencies and its
    ///     doubt on. `nil` means "is one of `nestedPackages`", for an in-memory tree.
    ///   - manifest: the text of the manifest in a root-relative directory (`""` is the root), or
    ///     `nil` when it cannot be read — which is doubt, so every nested package is in.
    public static func compiledNestedPackages(
        _ nestedPackages: Set<String>,
        rootHasManifest: Bool,
        rootPath: String,
        resolvingSymlinks: (String) -> String = { $0 },
        holdsManifest: ((String) -> Bool)? = nil,
        manifest: (String) -> String?
    ) -> Set<String> {
        guard rootHasManifest, !nestedPackages.isEmpty else { return nestedPackages }
        let isPackage = holdsManifest ?? nestedPackages.contains
        var reached: Set<String> = []
        var pending = [""]
        while let directory = pending.popLast() {
            guard let text = manifest(directory),
                  let dependencies = localPackageDependencies(manifest: text) else { return nestedPackages }
            for literal in dependencies {
                // The root is no nested package, whatever a `.package(path: ".")` says.
                guard let resolved = resolve(literal, from: directory, rootPath: rootPath, with: resolvingSymlinks),
                      !resolved.isEmpty,
                      isPackage(resolved),
                      reached.insert(resolved).inserted else { continue }
                pending.append(resolved)
            }
        }
        return reached
    }

    /// The nested package `relativePath` belongs to — the nearest of `nestedPackages` above it —
    /// or `nil` when it belongs to the root's own package.
    public static func owningPackage(of relativePath: String, among nestedPackages: Set<String>) -> String? {
        var directories = relativePath.split(separator: "/").dropLast().map(String.init)
        while !directories.isEmpty {
            let directory = directories.joined(separator: "/")
            if nestedPackages.contains(directory) { return directory }
            directories.removeLast()
        }
        return nil
    }

    /// `literal` resolved from the root-relative `directory`, standardised (`.` and `..` folded over
    /// the whole absolute path, lexically, as SwiftPM folds them), then resolved through symlinks
    /// (amendment H), as a root-relative path without a trailing `/`; `nil` when the result is not
    /// under the root. `rootPath` went through the same `resolvingSymlinks`, so a `/private/tmp/…`
    /// literal under a `/tmp/…` root, a dependency reached through a symlinked directory, and one
    /// spelled in another letter case each name the directory the compiler opens.
    static func resolve(
        _ literal: String,
        from directory: String,
        rootPath: String,
        with resolvingSymlinks: (String) -> String = { $0 }
    ) -> String? {
        let root = rootPath.split(separator: "/").map(String.init)
        let base = literal.hasPrefix("/") ? [] : root + directory.split(separator: "/").map(String.init)
        guard let lexical = standardised(base + literal.split(separator: "/").map(String.init)) else { return nil }
        let absolute = resolvingSymlinks("/" + lexical.joined(separator: "/")).split(separator: "/").map(String.init)
        guard absolute.starts(with: root) else { return nil }
        return absolute.dropFirst(root.count).joined(separator: "/")
    }

    /// `components` with `.` dropped and `..` folded, or `nil` when `..` climbs above `/`.
    private static func standardised(_ components: [String]) -> [String]? {
        var result: [String] = []
        for component in components where component != "." {
            if component == ".." {
                guard !result.isEmpty else { return nil }
                result.removeLast()
            } else {
                result.append(component)
            }
        }
        return result
    }
}

/// The `path:` arguments of a manifest's `.package(…)` calls, in source order.
private final class PathDependencyCollector: SyntaxVisitor {

    private(set) var paths: [String] = []
    /// False once a `.package(…)` call passes `path:` something that is not a plain literal.
    private(set) var isReadable = true

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "package",
              let path = node.arguments.first(where: { $0.label?.text == "path" }) else {
            return .visitChildren
        }
        // The value the compiler sees, not the source text: `"Pack\u{61}ges/A"` is `Packages/A`,
        // and so is `#"Packages/A"#`. Interpolation, or a literal that did not parse, is `nil`.
        if let literal = path.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue {
            paths.append(literal)
        } else {
            isReadable = false
        }
        return .visitChildren
    }
}
