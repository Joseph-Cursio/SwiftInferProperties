import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M5 — SwiftSyntax pass detecting Cardinality witnesses (≥ 2
/// stored fields that look like mutually-exclusive presentation
/// flags) inside a named State struct.
///
/// **Two entries** (mirrors `ConservationWitnessDetector` shape):
///   - `detect(stateTypeName:in source:)` — pure source-level entry
///   - `detect(stateTypeName:in directory:)` — directory walk
///
/// **Returns at most one witness per State struct** — see
/// `CardinalityWitness` doc. Returns `nil` (via empty array) when
/// fewer than 2 presentation fields are detected.
public enum CardinalityWitnessDetector {

    /// V2.0 M5 — detect a Cardinality witness in `source`. Returns
    /// at most one witness; empty array when fewer than 2 fields
    /// match. Pure.
    public static func detect(
        stateTypeName: String,
        in source: String
    ) -> [CardinalityWitness] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor(targetName: stateTypeName)
        visitor.walk(tree)
        return visitor.fields.count >= 2 ? [CardinalityWitness(fields: visitor.fields)] : []
    }

    /// V2.0 M5 — detect across every `.swift` file under `directory`.
    /// Concatenates fields across all files matching the target
    /// type (rare in practice — State typically lives in one file —
    /// but `extension Inbox.State { ... }` could legitimately split
    /// the fields), then emits one witness if `≥ 2` total.
    public static func detect(
        stateTypeName: String,
        in directory: URL
    ) throws -> [CardinalityWitness] {
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
        var allFields: [CardinalityWitness.Field] = []
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let tree = Parser.parse(source: source)
            let visitor = Visitor(targetName: stateTypeName)
            visitor.walk(tree)
            allFields.append(contentsOf: visitor.fields)
        }
        return allFields.count >= 2 ? [CardinalityWitness(fields: allFields)] : []
    }

    // MARK: - Visitor

    private final class Visitor: SyntaxVisitor {
        let targetComponents: [String]
        var typeStack: [String] = []
        var fields: [CardinalityWitness.Field] = []

        init(targetName: String) {
            self.targetComponents = targetName.split(separator: ".").map(String.init)
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                fields.append(contentsOf:
                    CardinalityFieldExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                fields.append(contentsOf:
                    CardinalityFieldExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            return .visitChildren
        }
        override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

        private func matchesTarget() -> Bool {
            guard typeStack.count >= targetComponents.count else { return false }
            let suffix = typeStack.suffix(targetComponents.count)
            return Array(suffix) == targetComponents
        }
    }
}

/// V2.0 M5 — extracts Cardinality presentation fields from one
/// member block. Pure; testable in isolation.
enum CardinalityFieldExtractor {

    /// Bool field name patterns. Case-sensitive: Swift's convention
    /// is `isShowing` / `isPresentingSheet`, not `IS_SHOWING` /
    /// `showing`. Required substrings rather than strict prefix —
    /// `isItemShowing` and `showingPanel` both qualify.
    private static let boolNamePatterns: [String] = [
        "Showing", "Presenting"
    ]

    /// Optional field name patterns. Lowercased compare — TCA's
    /// convention is `activeSheet` / `activeAlert` / `fullScreenCover`
    /// / `popover`, which all contain one of these substrings after
    /// lowering.
    private static let optionalNamePatterns: [String] = [
        "sheet", "alert", "fullscreencover", "popover"
    ]

    /// V1.94 (cycle-91 — TCA family-pattern calibration #1) — TCA
    /// presentation-property-wrapper attribute names. An Optional
    /// field carrying either of these attributes is treated as a
    /// presentation slot regardless of property name, since the
    /// wrapper itself encodes the presentation semantics. Modern
    /// TCA (1.0+) uses `@Presents`; the older `@PresentationState`
    /// alias is recognized for back-compat. Cycle-3 measurement on
    /// TCA 1.25.5 showed only 3 cardinality witnesses across 50
    /// reducers because every `@Presents var destination:
    /// Destination.State?` failed the name-pattern check (no
    /// "sheet" / "alert" substring in "destination").
    private static let presentationAttributeNames: Set<String> = [
        "Presents", "PresentationState"
    ]

    /// V2.0 M5 — walk the member block, route each stored property
    /// into either the bool-flag bucket or the optional-presentation
    /// bucket via the curated name patterns. V1.94 — Optional fields
    /// carrying `@Presents` / `@PresentationState` qualify regardless
    /// of name.
    static func extract(from memberBlock: MemberBlockSyntax) -> [CardinalityWitness.Field] {
        var result: [CardinalityWitness.Field] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let modifiers = varDecl.modifiers.map { $0.name.text }
            if modifiers.contains("static") || modifiers.contains("class") { continue }
            let hasPresentationAttribute = Self.declHasPresentationAttribute(varDecl)
            for binding in varDecl.bindings {
                if let field = classifyBinding(
                    binding,
                    hasPresentationAttribute: hasPresentationAttribute
                ) {
                    result.append(field)
                }
            }
        }
        return result
    }

    /// V1.94 — does the `VariableDeclSyntax` carry an `@Presents` or
    /// `@PresentationState` attribute? Used by `extract(from:)` to
    /// relax the name-pattern check for Optional fields with TCA
    /// presentation property wrappers.
    static func declHasPresentationAttribute(_ varDecl: VariableDeclSyntax) -> Bool {
        for element in varDecl.attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            let name = attribute.attributeName.trimmedDescription
            if presentationAttributeNames.contains(name) {
                return true
            }
        }
        return false
    }

    /// Classify one binding. Returns `nil` if the binding is
    /// computed, has no type annotation, or doesn't match either
    /// the Bool-flag or Optional-presentation patterns. V1.94 —
    /// when `hasPresentationAttribute` is `true`, an Optional binding
    /// qualifies regardless of property name.
    static func classifyBinding(
        _ binding: PatternBindingSyntax,
        hasPresentationAttribute: Bool = false
    ) -> CardinalityWitness.Field? {
        if binding.accessorBlock != nil { return nil }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { return nil }
        guard let typeAnnotation = binding.typeAnnotation else { return nil }
        let typeText = typeAnnotation.type.trimmedDescription
        let name = identifier.identifier.text
        if isBoolType(typeText), matchesBoolPattern(name) {
            return CardinalityWitness.Field(
                propertyName: name,
                indicator: "state.\(name)",
                kind: .boolFlag
            )
        }
        if isOptionalType(typeText),
           hasPresentationAttribute || matchesOptionalPattern(name) {
            return CardinalityWitness.Field(
                propertyName: name,
                indicator: "state.\(name) != nil",
                kind: .optionalPresentation
            )
        }
        return nil
    }

    /// `Bool` / `Swift.Bool` — exact match, trimmed.
    static func isBoolType(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        return trimmed == "Bool" || trimmed == "Swift.Bool"
    }

    /// Optional sigil `T?` or `Optional<T>` — name-based recognition.
    static func isOptionalType(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?") { return true }
        if trimmed.hasPrefix("Optional<") { return true }
        if trimmed.hasPrefix("Swift.Optional<") { return true }
        return false
    }

    /// Case-sensitive substring match against `boolNamePatterns`.
    static func matchesBoolPattern(_ name: String) -> Bool {
        boolNamePatterns.contains { name.contains($0) }
    }

    /// Case-insensitive substring match against `optionalNamePatterns`.
    static func matchesOptionalPattern(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return optionalNamePatterns.contains { lowered.contains($0) }
    }
}
