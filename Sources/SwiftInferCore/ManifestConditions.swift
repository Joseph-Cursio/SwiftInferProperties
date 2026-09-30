import Foundation
import SwiftParser
import SwiftSyntax

/// The custom compilation conditions a package's `Package.swift` sets, read from its syntax.
///
/// Part of evaluating `#if` before scanning (`docs/plans/inactive-if-config-scope.md`). The reader follows
/// the manifest's literal structure, never its execution, and every imprecision leans towards KEEPING code:
/// a `.define` counts package-wide rather than per target, and one the reader cannot place — inside an
/// `if`, `guard` or `#if` of the manifest — is `unknown`, which keeps both branches of a `#if` on it.
/// Commented-out defines are trivia and never reach the tree, which is right: swift-collections turns
/// `COLLECTIONS_INTERNAL_CHECKS` on by uncommenting a line.
public struct ManifestConditions: Sendable, Equatable {

    /// Conditions the build sets.
    public let set: Set<String>
    /// Conditions the manifest may or may not set — a define under a manifest-level branch.
    public let unknown: Set<String>

    public init(set: Set<String>, unknown: Set<String> = []) {
        self.set = set
        self.unknown = unknown
    }

    /// `true` / `false` when the manifest decides `name`, `nil` when it cannot.
    public func isSet(_ name: String) -> Bool? {
        if set.contains(name) { return true }
        if unknown.contains(name) { return nil }
        return false
    }

    /// Reads `source`, a `Package.swift`: top-level `.define("X")` and `-DX` in `unsafeFlags`, filtered by
    /// `.when(platforms:configuration:traits:)` for a macOS debug build, and the traits enabled by
    /// `.default(enabledTraits:)`, closed over each enabled trait's own `enabledTraits`.
    public static func read(manifest source: String) -> Self {
        let tree = Parser.parse(source: source)
        let collector = ManifestCollector(viewMode: .sourceAccurate)
        collector.walk(tree)
        var traits = collector.defaultTraits
        var grew = true
        while grew {
            let implied = traits.flatMap { collector.traitImplications[$0] ?? [] }
            grew = !Set(implied).isSubset(of: traits)
            traits.formUnion(implied)
        }
        var set = traits
        var unknown: Set<String> = []
        for define in collector.defines {
            switch define.state(enabledTraits: traits) {
            case true?: set.insert(define.name)
            case nil: unknown.insert(define.name)
            case false?: break
            }
        }
        return Self(set: set, unknown: unknown.subtracting(set))
    }
}

/// One `.define` or `-D` flag and what gates it.
private struct ManifestDefine {
    let name: String
    let branched: Bool
    let platforms: [String]?
    let configuration: String?
    let traits: [String]?

    func state(enabledTraits: Set<String>) -> Bool? {
        if branched { return nil }
        if let platforms, !platforms.contains("macOS") { return false }
        if let configuration, configuration != "debug" { return false }
        if let traits, enabledTraits.isDisjoint(with: traits) { return false }
        return true
    }
}

private final class ManifestCollector: SyntaxVisitor {
    var defines: [ManifestDefine] = []
    var defaultTraits: Set<String> = []
    var traitImplications: [String: [String]] = [:]

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else { return .visitChildren }
        let arguments = node.arguments
        switch member.declName.baseName.text {
        case "define":
            if let name = arguments.first.flatMap({ Self.string($0.expression) }) {
                defines.append(Self.define(name, gatedBy: arguments.dropFirst().first?.expression, at: node))
            }

        case "unsafeFlags":
            let flags = arguments.first.map { Self.strings($0.expression) } ?? []
            for flag in flags where flag.hasPrefix("-D") && flag.count > 2 {
                let gate = arguments.dropFirst().first?.expression
                defines.append(Self.define(String(flag.dropFirst(2)), gatedBy: gate, at: node))
            }

        case "default":
            if let traits = Self.labeled("enabledTraits", in: arguments) {
                defaultTraits.formUnion(Self.strings(traits))
            }

        case "trait":
            if let name = Self.labeled("name", in: arguments).flatMap(Self.string),
               let implied = Self.labeled("enabledTraits", in: arguments) {
                traitImplications[name, default: []] += Self.strings(implied)
            }

        default:
            break
        }
        return .visitChildren
    }

    private static func define(_ name: String, gatedBy condition: ExprSyntax?, at node: some SyntaxProtocol)
        -> ManifestDefine {
        let when = condition?.as(FunctionCallExprSyntax.self)
        let whenArguments = when?.arguments
        return ManifestDefine(
            name: name,
            branched: isBranched(node),
            platforms: labeled("platforms", in: whenArguments).map(memberNames),
            configuration: labeled("configuration", in: whenArguments).flatMap { memberNames($0).first },
            traits: labeled("traits", in: whenArguments).map(strings)
        )
    }

    /// A define under an `if`, `guard`, `switch` or `#if` of the manifest runs only on some paths.
    private static func isBranched(_ node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let parent = current {
            if parent.is(IfExprSyntax.self) || parent.is(GuardStmtSyntax.self)
                || parent.is(SwitchExprSyntax.self) || parent.is(IfConfigClauseSyntax.self) {
                return true
            }
            current = parent.parent
        }
        return false
    }

    private static func labeled(_ label: String, in arguments: LabeledExprListSyntax?) -> ExprSyntax? {
        arguments?.first { $0.label?.text == label }?.expression
    }

    private static func string(_ expr: ExprSyntax) -> String? {
        guard let literal = expr.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else { return nil }
        return segment.content.text
    }

    private static func strings(_ expr: ExprSyntax) -> [String] {
        expr.as(ArrayExprSyntax.self)?.elements.compactMap { string($0.expression) } ?? []
    }

    /// `[.macOS, .iOS]` → `["macOS", "iOS"]`; `.debug` → `["debug"]`.
    private static func memberNames(_ expr: ExprSyntax) -> [String] {
        if let member = expr.as(MemberAccessExprSyntax.self) { return [member.declName.baseName.text] }
        return expr.as(ArrayExprSyntax.self)?.elements.flatMap { memberNames($0.expression) } ?? []
    }
}
