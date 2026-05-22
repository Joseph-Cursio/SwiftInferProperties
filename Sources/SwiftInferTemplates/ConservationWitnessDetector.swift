import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M4.B — SwiftSyntax pass detecting Conservation witnesses
/// (stored count-shaped aggregate paired with an array collection)
/// inside a named State struct.
///
/// **Two entries:**
///   - `detect(stateTypeName:in source:)` — pure, takes a source
///     string. Used by tests; primary unit-of-test.
///   - `detect(stateTypeName:in directory:)` — walks `.swift` files
///     under `directory`, runs the source-level detector on each.
///
/// **Matching strategy.** The `stateTypeName` parameter is the M1
/// `ReducerCandidate.stateTypeName` (e.g. `"Inbox.State"` for a
/// nested type, or `"AppState"` for a top-level). The detector
/// matches either:
///   - A top-level type named `<stateTypeName>` (no dots), OR
///   - A type named `State` (the last component) nested under a
///     type whose name is the prefix component.
///
/// **What counts as count-shaped.** Aggregate name must contain
/// `count` (case-insensitive) — `count`, `itemCount`, `numEntries`,
/// `entryCount`, `numItems`. Type must resolve to an integer
/// (`Int`, `UInt`, signed/unsigned of any width). Floating-point
/// aggregates are excluded at detection time per PRD §5.2's
/// counter-signal.
public enum ConservationWitnessDetector {

    /// V2.0 M4.B — detect Conservation witnesses in `source`. Pure;
    /// returns witnesses in source order.
    public static func detect(
        stateTypeName: String,
        in source: String
    ) -> [ConservationWitness] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor(targetName: stateTypeName)
        visitor.walk(tree)
        return visitor.witnesses
    }

    /// V2.0 M4.B — detect Conservation witnesses across every
    /// `.swift` file under `directory`. Sorted-path walk so the
    /// merged output is order-deterministic — same posture as
    /// `ReducerDiscoverer.discover(directory:)`.
    public static func detect(
        stateTypeName: String,
        in directory: URL
    ) throws -> [ConservationWitness] {
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
        var witnesses: [ConservationWitness] = []
        for fileURL in swiftFiles {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            witnesses.append(contentsOf: detect(stateTypeName: stateTypeName, in: source))
        }
        return witnesses
    }

    // MARK: - Visitor

    /// V2.0 M4.B — internal SyntaxVisitor that walks struct / class
    /// declarations looking for the target State type. When found,
    /// pairs stored aggregate + array properties via
    /// `ConservationWitnessExtractor`.
    private final class Visitor: SyntaxVisitor {
        let targetName: String
        let targetComponents: [String]
        var typeStack: [String] = []
        var witnesses: [ConservationWitness] = []

        init(targetName: String) {
            self.targetName = targetName
            self.targetComponents = targetName.split(separator: ".").map(String.init)
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                let extracted = ConservationWitnessExtractor.extract(from: node.memberBlock)
                witnesses.append(contentsOf: extracted)
            }
            return .visitChildren
        }
        override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                let extracted = ConservationWitnessExtractor.extract(from: node.memberBlock)
                witnesses.append(contentsOf: extracted)
            }
            return .visitChildren
        }
        override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            return .visitChildren
        }
        override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

        /// Does the current type-stack suffix match the target name's
        /// component sequence? `"Inbox.State"` matches `[Inbox, State]`;
        /// `"AppState"` matches `[AppState]`. Allows the target to be
        /// nested arbitrarily deep — the stack tail just has to match.
        private func matchesTarget() -> Bool {
            guard typeStack.count >= targetComponents.count else { return false }
            let suffix = typeStack.suffix(targetComponents.count)
            return Array(suffix) == targetComponents
        }
    }
}

/// V2.0 M4.B — extracts Conservation witnesses from one member
/// block. Pure; testable in isolation.
enum ConservationWitnessExtractor {

    /// Count-shape recognition: the aggregate name must contain
    /// `count` (case-insensitive). Covers `count`, `itemCount`,
    /// `numEntries`-via-pluralization is NOT covered yet — only
    /// names containing the literal substring `count`. Recalibrate
    /// after the first calibration cycle if real corpora show
    /// different naming.
    static func nameLooksLikeCount(_ name: String) -> Bool {
        name.lowercased().contains("count")
    }

    /// Integer-type recognition. Matches `Int`, `UInt`, `Int8`,
    /// `Int16`, `Int32`, `Int64`, `UInt8`, `UInt16`, `UInt32`,
    /// `UInt64`, and their `Swift.`-prefixed equivalents. Floating-
    /// point types (`Double` / `Float` / `Float80`) and arbitrary-
    /// precision types are *not* count-shaped per PRD §5.2.
    static func typeLooksLikeIntegerCount(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        let recognized: Set<String> = [
            "Int", "UInt",
            "Int8", "Int16", "Int32", "Int64",
            "UInt8", "UInt16", "UInt32", "UInt64",
            "Swift.Int", "Swift.UInt",
            "Swift.Int8", "Swift.Int16", "Swift.Int32", "Swift.Int64",
            "Swift.UInt8", "Swift.UInt16", "Swift.UInt32", "Swift.UInt64"
        ]
        return recognized.contains(trimmed)
    }

    /// Returns the element type if `type` is an array literal `[T]`,
    /// nil otherwise. Matches the bracket-wrapped form only — explicit
    /// `Array<T>` is intentionally deferred (the bracket form is the
    /// idiomatic Swift convention; calibration can widen if needed).
    static func arrayElementType(_ type: String) -> String? {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        // Reject dictionary literal `[K: V]` — contains a top-level colon.
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

    /// Extract every (count-shaped aggregate, array collection) pair
    /// from `memberBlock`. Pairs by Cartesian product — if a State
    /// has 2 count-shaped properties and 3 array properties, we emit
    /// 6 witnesses. Calibration may tighten this (e.g. require
    /// name-prefix matches like `itemCount` ↔ `items`).
    static func extract(from memberBlock: MemberBlockSyntax) -> [ConservationWitness] {
        let (aggregates, collections) = classifyMembers(memberBlock)
        var witnesses: [ConservationWitness] = []
        for aggregate in aggregates {
            for collection in collections {
                witnesses.append(ConservationWitness(
                    aggregatePropertyName: aggregate.name,
                    aggregateTypeName: aggregate.typeText,
                    collectionPropertyName: collection.name,
                    elementTypeName: collection.elementTypeText
                ))
            }
        }
        return witnesses
    }

    /// Walk a member block once, returning each stored property
    /// classified as an aggregate (count-shaped + integer) or a
    /// collection (array literal). Skips computed / static / class
    /// properties. Extracted from `extract(from:)` to keep the
    /// outer function under SwiftLint's cyclomatic-complexity cap.
    private static func classifyMembers(
        _ memberBlock: MemberBlockSyntax
    ) -> (
        aggregates: [(name: String, typeText: String)],
        collections: [(name: String, elementTypeText: String)]
    ) {
        var aggregates: [(name: String, typeText: String)] = []
        var collections: [(name: String, elementTypeText: String)] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let modifiers = varDecl.modifiers.map(\.name.text)
            if modifiers.contains("static") || modifiers.contains("class") { continue }
            for binding in varDecl.bindings {
                classifyBinding(
                    binding,
                    aggregates: &aggregates,
                    collections: &collections
                )
            }
        }
        return (aggregates, collections)
    }

    /// Classify one binding (one identifier in a `var x: T` decl).
    /// Drops computed properties + bindings without an explicit
    /// type annotation, then routes the typed binding into either
    /// the aggregate or collection bucket. Pure; mutates the
    /// supplied accumulators.
    private static func classifyBinding(
        _ binding: PatternBindingSyntax,
        aggregates: inout [(name: String, typeText: String)],
        collections: inout [(name: String, elementTypeText: String)]
    ) {
        if binding.accessorBlock != nil { return }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { return }
        guard let typeAnnotation = binding.typeAnnotation else { return }
        let typeText = typeAnnotation.type.trimmedDescription
        let name = identifier.identifier.text
        if nameLooksLikeCount(name), typeLooksLikeIntegerCount(typeText) {
            aggregates.append((name, typeText))
        } else if let element = arrayElementType(typeText) {
            collections.append((name, element))
        }
    }
}
