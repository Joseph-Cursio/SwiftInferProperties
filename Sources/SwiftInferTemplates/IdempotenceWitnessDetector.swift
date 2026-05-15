import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M4.C — SwiftSyntax pass detecting Idempotence witnesses
/// (Action enum cases whose name suggests applying-twice equals
/// applying-once) inside a named Action enum.
///
/// **Two entries:**
///   - `detect(actionTypeName:in source:)` — pure, takes a source
///     string. Used by tests.
///   - `detect(actionTypeName:in directory:)` — walks `.swift`
///     files under `directory`. Sorted-path walk for byte-stable
///     output, same posture as Conservation's detector.
///
/// **Matching strategy.** Same suffix-match as
/// `ConservationWitnessDetector` — the `actionTypeName` parameter
/// is the M1 `ReducerCandidate.actionTypeName` (e.g. `"Inbox.Action"`
/// for a nested enum, `"AppAction"` for a top-level). Type-stack
/// suffix has to match the dotted name's components.
///
/// **Name patterns recognized.** Two pattern kinds:
///   - **Exact**: `refresh`, `reset`, `clear`, `dismiss`, `cancel`,
///     `close`, `hide`. Idempotent at the structural level.
///   - **Prefix**: `set*`, `select*`, `show*`, `present*`,
///     `dismiss*`. Cases like `setColor(_:)` are idempotent for a
///     fixed payload — the verifier generates the same payload
///     twice in succession.
public enum IdempotenceWitnessDetector {

    /// Exact-match names. Lowercased; case-insensitive compare at
    /// detection time. Curated set — calibration may widen if real
    /// corpora show common idempotent names we miss. `select` is
    /// included because PRD §5.3's example specifically calls out
    /// `select(id)` as idempotent (selecting the same id twice =
    /// selecting once); the prefix arm still catches `selectFoo` /
    /// `selectMessage` for prefix variants.
    static let exactNames: Set<String> = [
        "refresh", "reset", "clear", "dismiss", "cancel", "close", "hide",
        "select"
    ]

    /// Prefix-match names. The case identifier must start with one
    /// of these AND have additional characters after the prefix
    /// (so `set` alone is exact-match-bound; `setColor` matches the
    /// prefix). Case-insensitive.
    static let namePrefixes: [String] = [
        "set", "select", "show", "present"
    ]

    /// V2.0 M4.C — detect Idempotence witnesses in `source`. Pure.
    public static func detect(
        actionTypeName: String,
        in source: String
    ) -> [IdempotenceWitness] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor(targetName: actionTypeName)
        visitor.walk(tree)
        return visitor.witnesses
    }

    /// V2.0 M4.C — detect Idempotence witnesses across every
    /// `.swift` file under `directory`.
    public static func detect(
        actionTypeName: String,
        in directory: URL
    ) throws -> [IdempotenceWitness] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var swiftFiles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles.append(url)
        }
        swiftFiles.sort { $0.path < $1.path }
        var witnesses: [IdempotenceWitness] = []
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            witnesses.append(contentsOf: detect(actionTypeName: actionTypeName, in: source))
        }
        return witnesses
    }

    /// V2.0 M4.C — classify a case name as exact-match, prefix-match,
    /// or no-match. Pure; testable in isolation.
    static func classify(_ caseName: String) -> IdempotenceWitness.MatchKind? {
        let lowered = caseName.lowercased()
        if exactNames.contains(lowered) {
            return .exactName
        }
        for prefix in namePrefixes {
            // Prefix match requires at least one additional character
            // after the prefix — otherwise `set` alone would route
            // through the prefix path, which the exact-match arm
            // already wouldn't catch and the prefix arm would loop
            // into "is `set` a real action name?".
            if lowered.hasPrefix(prefix), lowered.count > prefix.count {
                return .namePrefix
            }
        }
        return nil
    }

    // MARK: - Visitor

    /// Walks the syntax tree looking for the target Action enum.
    /// When found, extracts each case's name via
    /// `IdempotenceCaseExtractor.extract`.
    private final class Visitor: SyntaxVisitor {
        let targetComponents: [String]
        var typeStack: [String] = []
        var witnesses: [IdempotenceWitness] = []

        init(targetName: String) {
            self.targetComponents = targetName.split(separator: ".").map(String.init)
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                witnesses.append(contentsOf:
                    IdempotenceCaseExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            return .visitChildren
        }
        override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

        private func matchesTarget() -> Bool {
            guard typeStack.count >= targetComponents.count else { return false }
            let suffix = typeStack.suffix(targetComponents.count)
            return Array(suffix) == targetComponents
        }
    }
}

/// V2.0 M4.C — extracts Idempotence witnesses from one enum's
/// member block. Pure; testable in isolation.
enum IdempotenceCaseExtractor {

    /// Iterate `EnumCaseDeclSyntax` members, route each case name
    /// through `IdempotenceWitnessDetector.classify`. Multi-element
    /// cases (`case foo, bar`) produce one witness per element.
    static func extract(from memberBlock: MemberBlockSyntax) -> [IdempotenceWitness] {
        var witnesses: [IdempotenceWitness] = []
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                let name = element.name.text
                if let kind = IdempotenceWitnessDetector.classify(name) {
                    witnesses.append(IdempotenceWitness(actionCaseName: name, matchKind: kind))
                }
            }
        }
        return witnesses
    }
}
