import Foundation
import SwiftSyntax

/// Whether a package shows any sign of The Composable Architecture — the one fact that lets the purity
/// question read `Effect`, `EffectOf` and `EffectTask` as the package's own names
/// (`ReducerPurityAnalyzer.analyzeForPurity`).
///
/// **The whole package, never one file.** A TCA module commonly imports TCA once, as
/// `@_exported import ComposableArchitecture`, and its feature files import nothing; a file-scoped
/// check reads every one of those as non-TCA. So a single sign anywhere answers `true` for every file:
/// - an import of `ComposableArchitecture` in any universe file, at any `#if` depth, in any clause,
///   with any attribute or import kind (`import struct ComposableArchitecture.Effect` counts);
/// - TCA named in the root's `Package.swift` or `Package.resolved`, or in an Xcode project's resolved
///   packages, which is how a feature kit that re-exports TCA under another name is still seen.
///
/// Erring here costs only precision: a `true` keeps the routing answer, which is what every package
/// got before this existed.
public enum TCAPresence {

    /// `true` when any tree imports TCA or the root's manifests name it.
    public static func shows(in trees: [SourceFileSyntax], root: URL?) -> Bool {
        trees.contains(where: importsComposableArchitecture) || manifestsNameTCA(at: root)
    }

    /// An import of `ComposableArchitecture` among `file`'s statements, descending into every clause of
    /// every `#if` without evaluating its condition.
    static func importsComposableArchitecture(_ file: SourceFileSyntax) -> Bool {
        imports(in: file.statements)
    }

    private static func imports(in statements: CodeBlockItemListSyntax) -> Bool {
        statements.contains { statement in
            if let declaration = statement.item.as(ImportDeclSyntax.self) {
                return declaration.path.first?.name.text == "ComposableArchitecture"
            }
            guard let conditional = statement.item.as(IfConfigDeclSyntax.self) else { return false }
            return conditional.clauses.contains { clause in
                guard case let .statements(nested)? = clause.elements else { return false }
                return imports(in: nested)
            }
        }
    }

    /// The package's own manifests, read as text: `swift-composable-architecture` appears in a
    /// dependency's URL and in its resolved identity alike.
    static func manifestsNameTCA(at root: URL?) -> Bool {
        guard let root else { return false }
        let fileManager = FileManager.default
        var manifests = ["Package.swift", "Package.resolved"].map { root.appendingPathComponent($0) }
        let entries = (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        for project in entries where project.hasSuffix(".xcodeproj") || project.hasSuffix(".xcworkspace") {
            let base = root.appendingPathComponent(project)
            manifests.append(base.appendingPathComponent("project.xcworkspace/xcshareddata/swiftpm/Package.resolved"))
            manifests.append(base.appendingPathComponent("xcshareddata/swiftpm/Package.resolved"))
        }
        return manifests.contains { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
            return text.range(of: "composable-architecture", options: .caseInsensitive) != nil
        }
    }
}
