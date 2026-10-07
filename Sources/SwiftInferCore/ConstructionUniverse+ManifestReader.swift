import SwiftParser
import SwiftSyntax

/// What a manifest says about the packages the closure reaches — its local dependencies and its
/// targets' paths — read by parsing it, as the shared spec's amendments B, H, K, O and P require,
/// word for word with SwiftProjectLint and pinned by the shared `construction-universe-cases.json`.
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
        read(manifest).dependencies
    }

    /// The `path:` values of `manifest`'s target-like calls — `.target`, `.executableTarget`,
    /// `.testTarget`, `.plugin`, `.macro`, `.systemLibrary`, `.binaryTarget` — in source order, read
    /// as `localPackageDependencies(manifest:)` reads a dependency (amendment P), or `nil` when one
    /// passes `path:` anything but a string literal without interpolation (doubt).
    ///
    /// A target whose `path:` lies inside a nested package compiles that package's files as the
    /// root's own: `.target(name: "Core", path: "Core/Sources/Core")` beside a `Core/Package.swift`
    /// the root never names as a dependency. So a nested package holding a resolved target path is
    /// reached, with its own closure. It over-includes harmlessly — the predicate still decides
    /// which files are production.
    public static func localTargetPaths(manifest: String) -> [String]? {
        read(manifest).targetPaths
    }

    /// One directory's manifests' literals — the union over its `Package.swift` and every
    /// `Package@swift-*.swift` beside it (amendment O) — or `nil` when any one is doubt.
    struct ManifestLiterals {
        var dependencies: [String] = []
        var targetPaths: [String] = []
    }

    /// The union of `manifests`' literals, or `nil` for doubt: a manifest that cannot be read, or one
    /// that passes `path:` anything but a literal, to a dependency or to a target.
    static func literals(of manifests: [Manifest]) -> ManifestLiterals? {
        var literals = ManifestLiterals()
        for manifest in manifests {
            switch manifest {
            case .absent:
                continue

            case .unreadable:
                return nil

            case .text(let text):
                let read = read(text)
                guard let dependencies = read.dependencies, let targetPaths = read.targetPaths else { return nil }
                literals.dependencies += dependencies
                literals.targetPaths += targetPaths
            }
        }
        return literals
    }

    /// Both readings of `manifest`, from one parse on a large stack.
    private static func read(_ manifest: String) -> (dependencies: [String]?, targetPaths: [String]?) {
        LargeStackWorkers.run {
            let collector = ManifestPathCollector(viewMode: .sourceAccurate)
            collector.walk(Parser.parse(source: manifest))
            return (
                collector.dependenciesAreLiteral ? collector.dependencies : nil,
                collector.targetPathsAreLiteral ? collector.targetPaths : nil
            )
        }
    }
}

/// The `path:` arguments of a manifest's `.package(…)` calls and of its target-like calls, in
/// source order.
private final class ManifestPathCollector: SyntaxVisitor {

    static let targetKinds: Set<String> = [
        "target", "executableTarget", "testTarget", "plugin", "macro", "systemLibrary", "binaryTarget"
    ]

    private(set) var dependencies: [String] = []
    private(set) var targetPaths: [String] = []
    /// False once a `.package(…)` call passes `path:` something that is not a plain literal.
    private(set) var dependenciesAreLiteral = true
    /// False once a target-like call does.
    private(set) var targetPathsAreLiteral = true

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              let path = node.arguments.first(where: { $0.label?.text == "path" }) else {
            return .visitChildren
        }
        let name = member.declName.baseName.text
        guard name == "package" || Self.targetKinds.contains(name) else { return .visitChildren }
        // The value the compiler sees, not the source text: `"Pack\u{61}ges/A"` is `Packages/A`,
        // and so is `#"Packages/A"#`. Interpolation, or a literal that did not parse, is `nil`.
        let value = path.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
        if name == "package" {
            if let value { dependencies.append(value) } else { dependenciesAreLiteral = false }
        } else {
            if let value { targetPaths.append(value) } else { targetPathsAreLiteral = false }
        }
        return .visitChildren
    }
}
