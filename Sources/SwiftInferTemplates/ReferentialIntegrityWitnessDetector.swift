import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M6 — SwiftSyntax pass detecting Referential Integrity
/// witnesses (a "selected" Optional ID field paired with an array
/// collection) inside a named State struct.
///
/// **Two entries** (mirrors Conservation / Cardinality detector
/// shape):
///   - `detect(stateTypeName:in source:)` — pure source-level entry
///   - `detect(stateTypeName:in directory:)` — directory walk
///
/// **Cartesian-product pairing.** Every "selected" Optional × every
/// array collection in the State produces one witness. v0.0
/// deliberately broad; calibration cycles will narrow.
public enum ReferentialIntegrityWitnessDetector {

    /// V2.0 M6 — detect witnesses in `source`. Pure.
    public static func detect(
        stateTypeName: String,
        in source: String
    ) -> [ReferentialIntegrityWitness] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor(targetName: stateTypeName)
        visitor.walk(tree)
        return visitor.witnesses
    }

    /// V2.0 M6 — detect across every `.swift` file under `directory`.
    public static func detect(
        stateTypeName: String,
        in directory: URL
    ) throws -> [ReferentialIntegrityWitness] {
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
        var witnesses: [ReferentialIntegrityWitness] = []
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            witnesses.append(contentsOf: detect(stateTypeName: stateTypeName, in: source))
        }
        return witnesses
    }

    // MARK: - Visitor

    private final class Visitor: SyntaxVisitor {
        let targetComponents: [String]
        var typeStack: [String] = []
        var witnesses: [ReferentialIntegrityWitness] = []

        init(targetName: String) {
            self.targetComponents = targetName.split(separator: ".").map(String.init)
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                witnesses.append(contentsOf:
                    ReferentialIntegrityExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                witnesses.append(contentsOf:
                    ReferentialIntegrityExtractor.extract(from: node.memberBlock)
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

/// V2.0 M6 — extracts Referential Integrity witnesses from one
/// member block. Pure; testable in isolation.
enum ReferentialIntegrityExtractor {

    /// Name-prefix check: case-insensitive `selected` prefix. Covers
    /// `selectedID`, `selectedMessageID`, `selectedItem`,
    /// `SelectedID`, etc. Bare `selected` (length 8 exact) also
    /// counts — the constraint is *starts with* `selected`.
    static func nameLooksLikeSelected(_ name: String) -> Bool {
        name.lowercased().hasPrefix("selected")
    }

    /// V2.0 M6 — walk the member block, partition into "selected
    /// Optional" + "Array collection" buckets, emit one witness
    /// per Cartesian-product pair.
    static func extract(from memberBlock: MemberBlockSyntax) -> [ReferentialIntegrityWitness] {
        let (selectedOpts, collections) = classify(memberBlock)
        var witnesses: [ReferentialIntegrityWitness] = []
        for selected in selectedOpts {
            for collection in collections {
                witnesses.append(ReferentialIntegrityWitness(
                    selectedPropertyName: selected.name,
                    selectedTypeName: selected.typeText,
                    collectionPropertyName: collection.name,
                    elementTypeName: collection.elementTypeText
                ))
            }
        }
        return witnesses
    }

    /// Walk one member block, returning each stored property
    /// classified as either a selected-Optional or an array
    /// collection. Computed / static / class-static properties
    /// skipped. Extracted from `extract(from:)` to keep the outer
    /// function under SwiftLint's cyclomatic-complexity cap.
    private static func classify(
        _ memberBlock: MemberBlockSyntax
    ) -> (
        selectedOpts: [(name: String, typeText: String)],
        collections: [(name: String, elementTypeText: String)]
    ) {
        var selectedOpts: [(name: String, typeText: String)] = []
        var collections: [(name: String, elementTypeText: String)] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let modifiers = varDecl.modifiers.map { $0.name.text }
            if modifiers.contains("static") || modifiers.contains("class") { continue }
            for binding in varDecl.bindings {
                classifyBinding(
                    binding,
                    selectedOpts: &selectedOpts,
                    collections: &collections
                )
            }
        }
        return (selectedOpts, collections)
    }

    private static func classifyBinding(
        _ binding: PatternBindingSyntax,
        selectedOpts: inout [(name: String, typeText: String)],
        collections: inout [(name: String, elementTypeText: String)]
    ) {
        if binding.accessorBlock != nil { return }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { return }
        guard let typeAnnotation = binding.typeAnnotation else { return }
        let typeText = typeAnnotation.type.trimmedDescription
        let name = identifier.identifier.text
        if nameLooksLikeSelected(name), isOptionalType(typeText) {
            selectedOpts.append((name, typeText))
        } else if let element = arrayElementType(typeText) {
            collections.append((name, element))
        }
    }

    /// Optional sigil `T?` or `Optional<T>` — same recognition as
    /// `CardinalityFieldExtractor.isOptionalType`.
    static func isOptionalType(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?") { return true }
        if trimmed.hasPrefix("Optional<") { return true }
        if trimmed.hasPrefix("Swift.Optional<") { return true }
        return false
    }

    /// Returns the element type if `type` is an array literal `[T]`,
    /// nil otherwise. Mirrors
    /// `ConservationWitnessExtractor.arrayElementType`'s
    /// depth-counting parser so generic args don't trip the
    /// dictionary check.
    static func arrayElementType(_ type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("[") && trimmed.hasSuffix("]") else { return nil }
        let inner = String(trimmed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespaces)
        var depth = 0
        for char in inner {
            switch char {
            case "<", "(", "[": depth += 1
            case ">", ")", "]": depth -= 1
            case ":" where depth == 0: return nil
            default: break
            }
        }
        return inner
    }
}
