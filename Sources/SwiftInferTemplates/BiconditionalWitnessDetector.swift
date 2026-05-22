import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M7 — SwiftSyntax pass detecting Biconditional / iff
/// witnesses inside a named State struct.
///
/// **Pairing strategy.** Cartesian product of `is*`-shaped Bool
/// fields × all Optional fields. v0.0 deliberately broad per PRD
/// §5.6's calibration framing ("trickiest of the five families,
/// cycles 3-5 to dial precision").
public enum BiconditionalWitnessDetector {

    /// Bool name patterns. Case-sensitive substring match — Swift
    /// camelCase convention. `isLoadingResults` / `isShowingDetail`
    /// match; `loadingResults` (no `is`) doesn't qualify.
    static let boolNamePatterns: [String] = [
        "Loading", "Showing", "Presenting", "Active", "Fetching", "Refreshing"
    ]

    /// V2.0 M7 — detect witnesses in `source`. Pure.
    public static func detect(
        stateTypeName: String,
        in source: String
    ) -> [BiconditionalWitness] {
        let tree = Parser.parse(source: source)
        let visitor = Visitor(targetName: stateTypeName)
        visitor.walk(tree)
        return visitor.witnesses
    }

    /// V2.0 M7 — detect across every `.swift` file under `directory`.
    public static func detect(
        stateTypeName: String,
        in directory: URL
    ) throws -> [BiconditionalWitness] {
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
        var witnesses: [BiconditionalWitness] = []
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
        var witnesses: [BiconditionalWitness] = []

        init(targetName: String) {
            self.targetComponents = targetName.split(separator: ".").map(String.init)
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                witnesses.append(
                    contentsOf: BiconditionalExtractor.extract(from: node.memberBlock)
                )
            }
            return .visitChildren
        }
        override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            typeStack.append(node.name.text)
            if matchesTarget() {
                witnesses.append(
                    contentsOf: BiconditionalExtractor.extract(from: node.memberBlock)
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

/// V2.0 M7 — extracts Biconditional witnesses from one member block.
/// Pure; testable in isolation.
enum BiconditionalExtractor {

    /// V2.0 M7 — walk the member block, partition into Bool-flag +
    /// Optional buckets, emit one witness per Cartesian-product pair.
    ///
    /// V1.105 (cycle-102 Finding D fix) — suppress bicond pairings
    /// where both the Bool field AND the Optional field would
    /// already be classified as Cardinality presentation slots AND
    /// the cardinality witness covers **≥ 3 fields**. The 3+-slot
    /// cardinality encodes mutual-exclusion over multiple
    /// independent UI slots; bicond cross-pairings between those
    /// slots (e.g., `isShowingSheet × activeFullScreenCover` —
    /// unrelated presentation slots) are noise.
    ///
    /// The 2-slot cardinality case is deliberately NOT suppressed:
    /// `isShowingSheet` + `sheet: Sheet?` legitimately suggests both
    /// cardinality (`at most one`) AND biconditional (`bool iff
    /// non-nil`); calibration triage decides which the user wants.
    /// Combining both invariants over-constrains but doesn't break
    /// detection — the rubric handles the disambiguation.
    ///
    /// Real-corpus example (Hand03): State `{isShowingSheet,
    /// isShowingAlert, activeFullScreenCover}` produces a 3-slot
    /// cardinality witness. Pre-fix bicond also fired 2 cross-
    /// pairings (`isShowingSheet × cover`, `isShowingAlert × cover`)
    /// — both unrelated to the presentation contract. Post-fix
    /// both are suppressed.
    ///
    /// The filter is narrow: TCA's `isNavigationActive ×
    /// optionalCounter` shape stays intact because `optionalCounter`
    /// doesn't match the presentation-name patterns (and the State
    /// doesn't fire cardinality at all). Hand05's `isLoadingResults
    /// × cachedResult` stays intact for the same reason — neither
    /// field is a cardinality candidate. The triage rubric handles
    /// those semantic disambiguations.
    static func extract(from memberBlock: MemberBlockSyntax) -> [BiconditionalWitness] {
        let (boolFlags, optionals) = classify(memberBlock)
        let cardinalityFields = CardinalityFieldExtractor.extract(from: memberBlock)
        let cardinalityHasThreeOrMore = cardinalityFields.count >= 3
        let presentationFieldNames = Set(cardinalityFields.map(\.propertyName))
        var witnesses: [BiconditionalWitness] = []
        for boolField in boolFlags {
            for optionalField in optionals {
                if cardinalityHasThreeOrMore,
                   presentationFieldNames.contains(boolField.name),
                   presentationFieldNames.contains(optionalField.name) {
                    continue
                }
                witnesses.append(BiconditionalWitness(
                    boolPropertyName: boolField.name,
                    boolTypeName: boolField.typeText,
                    optionalPropertyName: optionalField.name,
                    optionalTypeName: optionalField.typeText
                ))
            }
        }
        return witnesses
    }

    /// Classify stored properties. Bool fields with matching name
    /// patterns route to the flag bucket; Optional fields (any
    /// shape) route to the optional bucket. Computed / static /
    /// class-static properties skipped.
    private static func classify(
        _ memberBlock: MemberBlockSyntax
    ) -> (
        boolFlags: [(name: String, typeText: String)],
        optionals: [(name: String, typeText: String)]
    ) {
        var boolFlags: [(name: String, typeText: String)] = []
        var optionals: [(name: String, typeText: String)] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            let modifiers = varDecl.modifiers.map(\.name.text)
            if modifiers.contains("static") || modifiers.contains("class") { continue }
            for binding in varDecl.bindings {
                classifyBinding(
                    binding,
                    boolFlags: &boolFlags,
                    optionals: &optionals
                )
            }
        }
        return (boolFlags, optionals)
    }

    private static func classifyBinding(
        _ binding: PatternBindingSyntax,
        boolFlags: inout [(name: String, typeText: String)],
        optionals: inout [(name: String, typeText: String)]
    ) {
        if binding.accessorBlock != nil { return }
        guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else { return }
        let name = identifier.identifier.text
        // V1.97 (cycle-94 fix for cycle-87 finding #5 sub-item (d)) —
        // recognize Bool fields declared without an explicit type
        // annotation but with a `true` / `false` literal initializer.
        // Modern TCA's idiomatic State shape is `var isLoading =
        // false` (no `: Bool`), and `04-NavigationStack.swift`'s
        // `(fact: String?, isLoading: <inferred Bool>)` is exactly
        // the biconditional pair the M7 detector is after — but the
        // prior typeAnnotation-required gate missed it. The
        // annotation-bearing path stays unchanged for Optional fields
        // (whose Optional-ness can't be inferred from a literal
        // without nullability info beyond what `nil` carries).
        if let typeAnnotation = binding.typeAnnotation {
            let typeText = typeAnnotation.type.trimmedDescription
            if isBoolType(typeText), nameLooksLikeBiconditionalFlag(name) {
                boolFlags.append((name, typeText))
            } else if isOptionalType(typeText) {
                optionals.append((name, typeText))
            }
            return
        }
        if isBoolLiteralInitializer(binding.initializer?.value),
           nameLooksLikeBiconditionalFlag(name) {
            boolFlags.append((name, "Bool"))
        }
    }

    /// V1.97 — does this initializer expression look like a `true` /
    /// `false` literal? Used by `classifyBinding` to recover the Bool
    /// type for `var isLoading = false`-style bindings where the
    /// programmer relies on type inference rather than an explicit
    /// `: Bool` annotation.
    static func isBoolLiteralInitializer(_ expression: ExprSyntax?) -> Bool {
        expression?.as(BooleanLiteralExprSyntax.self) != nil
    }

    /// `Bool` / `Swift.Bool`.
    static func isBoolType(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        return trimmed == "Bool" || trimmed == "Swift.Bool"
    }

    /// Optional sigil `T?` / `Optional<T>` / `Swift.Optional<T>`.
    static func isOptionalType(_ type: String) -> Bool {
        let trimmed = type.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix("?") { return true }
        if trimmed.hasPrefix("Optional<") { return true }
        if trimmed.hasPrefix("Swift.Optional<") { return true }
        return false
    }

    /// V2.0 M7 — case-sensitive substring match against
    /// `boolNamePatterns`. `isLoadingX` matches via "Loading";
    /// `isactive` doesn't (lowercase `a`).
    static func nameLooksLikeBiconditionalFlag(_ name: String) -> Bool {
        BiconditionalWitnessDetector.boolNamePatterns.contains { name.contains($0) }
    }
}
