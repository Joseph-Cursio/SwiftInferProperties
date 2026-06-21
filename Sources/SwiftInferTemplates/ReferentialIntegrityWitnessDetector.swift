import Foundation
import SwiftInferCore
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
        let swiftFiles = SwiftSourceFiles.sorted(in: directory)
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
                witnesses.append(
                    contentsOf: ReferentialIntegrityExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                witnesses.append(
                    contentsOf: ReferentialIntegrityExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_: ClassDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            return .visitChildren
        }
        override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }

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
    /// Optional" + "Array collection" buckets, emit one witness per
    /// Cartesian-product pair filtered by element-type compatibility.
    ///
    /// V1.104 (cycle-101a Finding C fix) — when a `selected<X>(ID)?`
    /// property exposes an implied element type via `impliedElementType
    /// (fromSelectedName:)`, only pair it with collections whose
    /// element type matches X (case-insensitive, ignoring module
    /// qualification). E.g., `selectedMessageID` pairs with
    /// `messages: [Message]` but not `drafts: [Draft]`. When the
    /// selected name has no extractable core (`selected`, `selectedID`),
    /// the filter falls back to the pre-fix Cartesian behavior, since
    /// no naming signal is available.
    ///
    /// Real-corpus motivation: HandRolled `MessageListReducer` State
    /// pairs `selectedMessageID: Message.ID?` against both
    /// `messages: [Message]` and `drafts: [Draft]`. Pre-fix, both
    /// pairings emitted suggestions; the drafts pairing is
    /// semantically wrong (a Message ID can't index into a Draft
    /// collection) and would be triaged as `.rejected` per the
    /// cycle-99 triage rubric. Post-fix, the drafts pairing is
    /// filtered out at detection time.
    static func extract(from memberBlock: MemberBlockSyntax) -> [ReferentialIntegrityWitness] {
        let (selectedOpts, collections) = classify(memberBlock)
        var witnesses: [ReferentialIntegrityWitness] = []
        for selected in selectedOpts {
            let implied = impliedElementType(fromSelectedName: selected.name)
            for collection in collections {
                if let implied,
                   !elementTypeMatches(implied: implied, collection: collection.elementTypeText) {
                    continue
                }
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

    /// V1.104 — extract the implied element type from a
    /// `selected<X>(ID)?` property name. Returns the substring after
    /// stripping the `selected` prefix and trailing `ID` suffix
    /// (both case-insensitive). Returns `nil` when the remaining
    /// core is empty (e.g., bare `selected`, `selectedID`,
    /// `selectedId`) — those preserve the pre-v1.104 Cartesian
    /// behavior because no element-type signal is available.
    static func impliedElementType(fromSelectedName name: String) -> String? {
        let lowered = name.lowercased()
        guard lowered.hasPrefix("selected") else { return nil }
        var core = String(name.dropFirst("selected".count))
        if core.lowercased().hasSuffix("id") {
            core = String(core.dropLast(2))
        }
        return core.isEmpty ? nil : core
    }

    /// V1.104 — does the collection's element type satisfy the
    /// selected property's implied element type? Matches if **any**
    /// dotted component of the collection's element-type text equals
    /// `implied` (case-insensitive). Two conventions both produce
    /// matches:
    ///
    ///   - `selectedMessageID` → implied `Message`; collection
    ///     `[Message]` or `[Inbox.Message]` → match on the `Message`
    ///     component. The `Inbox` qualifier is just module scope.
    ///   - `selectedTodoID` → implied `Todo`; collection
    ///     `IdentifiedArrayOf<Todo.State>` → element extracted as
    ///     `Todo.State`, match on the `Todo` component. This is TCA's
    ///     idiomatic convention: a Reducer named `Todo` defines its
    ///     `State` sub-type, and `selectedTodoID` references one of
    ///     those `Todo.State` records by their `ID`.
    ///
    /// Conservative: requires *some* component to match. Suppresses
    /// the cross-collection false-positive (`selectedMessageID` ×
    /// `[Draft]` — no shared component) while admitting both
    /// conventions.
    static func elementTypeMatches(implied: String, collection: String) -> Bool {
        let lowercasedImplied = implied.lowercased()
        let components = collection.split(separator: ".").map { $0.lowercased() }
        return components.contains(lowercasedImplied)
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
            let modifiers = varDecl.modifiers.map(\.name.text)
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
        } else if let element = collectionElementType(typeText) {
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

    /// V1.95 (cycle-92 — TCA family-pattern calibration #2) —
    /// element-type extraction across all recognized collection
    /// shapes. Tries the array-literal `[T]` shape first
    /// (`arrayElementType`), then the modern-TCA
    /// `IdentifiedArrayOf<T>` / `IdentifiedArray<ID, T>` shapes
    /// (`identifiedArrayElementType`). Cycle-3 measurement on TCA
    /// 1.25.5 showed referential integrity at 0 across all 50 reducers
    /// because every TCA State uses `IdentifiedArrayOf<X>` (not bare
    /// `[X]`) for its collections, and the detector only matched
    /// the array-literal form.
    static func collectionElementType(_ type: String) -> String? {
        if let element = arrayElementType(type) {
            return element
        }
        return identifiedArrayElementType(type)
    }

    /// Returns the element type if `type` is an array literal `[T]`,
    /// nil otherwise. Mirrors
    /// `ConservationWitnessExtractor.arrayElementType`'s
    /// depth-counting parser so generic args don't trip the
    /// dictionary check.
    static func arrayElementType(_ type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
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

    /// V1.95 — returns the element type if `type` is one of TCA's
    /// `IdentifiedArrayOf<T>` (typealias for `IdentifiedArray<T.ID, T>`)
    /// or the explicit `IdentifiedArray<ID, T>` two-argument form.
    /// For the two-argument form, the element type is the *second*
    /// generic argument (the first is the ID type). Returns nil for
    /// any other shape so the caller can fall through to
    /// non-collection classification.
    ///
    /// Module-prefix variants (`IdentifiedCollections.IdentifiedArrayOf`)
    /// are accepted alongside the bare names — real TCA code never
    /// uses the prefix but the detector stays robust.
    static func identifiedArrayElementType(_ type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix(">") else { return nil }
        for prefix in identifiedArrayOfPrefixes where trimmed.hasPrefix(prefix) {
            let inner = String(trimmed.dropFirst(prefix.count).dropLast())
                .trimmingCharacters(in: .whitespaces)
            return inner.isEmpty ? nil : inner
        }
        for prefix in identifiedArrayPrefixes where trimmed.hasPrefix(prefix) {
            let inner = String(trimmed.dropFirst(prefix.count).dropLast())
                .trimmingCharacters(in: .whitespaces)
            return secondGenericArgument(in: inner)
        }
        return nil
    }

    private static let identifiedArrayOfPrefixes = [
        "IdentifiedArrayOf<",
        "IdentifiedCollections.IdentifiedArrayOf<"
    ]

    private static let identifiedArrayPrefixes = [
        "IdentifiedArray<",
        "IdentifiedCollections.IdentifiedArray<"
    ]

    /// Depth-counting split on the top-level comma. `inner` is the
    /// generic-argument list without the enclosing `<>`. Returns
    /// the second comma-separated component (the element type for
    /// `IdentifiedArray<ID, Element>`), trimmed, or nil if the
    /// argument list isn't exactly 2 top-level components.
    private static func secondGenericArgument(in inner: String) -> String? {
        var depth = 0
        var commaIdx: String.Index?
        for index in inner.indices {
            let char = inner[index]
            switch char {
            case "<", "(", "[": depth += 1
            case ">", ")", "]": depth -= 1

            case "," where depth == 0:
                if commaIdx == nil {
                    commaIdx = index
                } else {
                    return nil
                }

            default:
                break
            }
        }
        guard let commaIdx else { return nil }
        let second = inner[inner.index(after: commaIdx)...]
            .trimmingCharacters(in: .whitespaces)
        return second.isEmpty ? nil : second
    }
}
