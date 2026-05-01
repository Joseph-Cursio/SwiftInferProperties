import Foundation
import ProtoLawCore
import SwiftParser
import SwiftSyntax

// swiftlint:disable file_length
// File contains the M2.5-extended scanner — function decls, body signals,
// identity candidates, and reducer-op seed classification all live here so
// the visitor walks the source tree exactly once. Splitting along the
// 400-line file limit would force the body / identity / seed visitors into
// separate files that have to be edited in lockstep.

/// Static-analysis pipeline that walks Swift source and emits one
/// `FunctionSummary` per function declaration. M1.2 surface — the M1.3+
/// scoring engine consumes the produced summaries without further parsing.
///
/// Coverage:
/// - Top-level functions and functions inside `class`, `struct`, `enum`,
///   `actor`, and `extension` decls. Containing-type stack tracks the
///   innermost enclosing type by source name; extensions contribute the
///   `extendedType` text (e.g. `"Array"`).
/// - Protocol *requirements* (function decls inside `protocol` bodies) are
///   intentionally skipped — they have no body to score against and the
///   templates fire on implementations.
/// - Nested function decls (functions declared inside another function's
///   body) are skipped — rare in idiomatic Swift, and including them would
///   conflate the body-signal scan with the outer function's signals.
public enum FunctionScanner {

    /// Scan a single in-memory source string. `file` is the label attached
    /// to every emitted `SourceLocation` — pass the path you want shown to
    /// the user (e.g. `Sources/MyTarget/MyFile.swift`).
    public static func scan(source: String, file: String) -> [FunctionSummary] {
        scanCorpus(source: source, file: file).summaries
    }

    /// Scan a single `.swift` file on disk. Reads the file as UTF-8.
    public static func scan(file: URL) throws -> [FunctionSummary] {
        let source = try String(contentsOf: file, encoding: .utf8)
        return scan(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`. Files are
    /// visited in deterministic (sorted-path) order so output is stable
    /// across runs — supports the byte-identical-reproducibility guarantee
    /// (PRD v0.3 §16 #6).
    public static func scan(directory: URL) throws -> [FunctionSummary] {
        try scanCorpus(directory: directory).summaries
    }

    /// One-pass scan that emits `FunctionSummary`, `IdentityCandidate`,
    /// and `TypeDecl` records from a single AST walk. Started in M2.5 for
    /// the identity-element template; M3.2 extended the same walk to
    /// emit `TypeDecl` records for M3.3's `EquatableResolver`. Keeps
    /// the §13 perf budget intact by avoiding a second pass over the
    /// source tree.
    public static func scanCorpus(source: String, file: String) -> ScannedCorpus {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = FunctionScannerVisitor(file: file, converter: converter)
        visitor.walk(tree)
        return ScannedCorpus(
            summaries: visitor.summaries,
            identities: visitor.identities,
            typeDecls: visitor.typeDecls
        )
    }

    /// Scan a single `.swift` file on disk. Reads the file as UTF-8.
    public static func scanCorpus(file: URL) throws -> ScannedCorpus {
        let source = try String(contentsOf: file, encoding: .utf8)
        return scanCorpus(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`. Files are
    /// visited in deterministic (sorted-path) order so the merged output
    /// is stable across runs.
    public static func scanCorpus(directory: URL) throws -> ScannedCorpus {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return .empty
        }
        var swiftFiles: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            swiftFiles.append(url)
        }
        swiftFiles.sort { $0.path < $1.path }
        var summaries: [FunctionSummary] = []
        var identities: [IdentityCandidate] = []
        var typeDecls: [TypeDecl] = []
        for fileURL in swiftFiles {
            let corpus = try scanCorpus(file: fileURL)
            summaries.append(contentsOf: corpus.summaries)
            identities.append(contentsOf: corpus.identities)
            typeDecls.append(contentsOf: corpus.typeDecls)
        }
        return ScannedCorpus(summaries: summaries, identities: identities, typeDecls: typeDecls)
    }
}

// MARK: - Visitor

// swiftlint:disable type_body_length
// The visitor coheres around its single AST walk — function decls,
// identity candidates, type decls, and the M4.1 member-block inspectors
// all live here so the source tree is traversed exactly once per file.
// Splitting along the 250-line body limit would force the per-decl
// helpers into separate visitor types that have to be edited in lockstep.
private final class FunctionScannerVisitor: SyntaxVisitor {

    var summaries: [FunctionSummary] = []
    var identities: [IdentityCandidate] = []
    var typeDecls: [TypeDecl] = []
    private let file: String
    private let converter: SourceLocationConverter
    private var typeStack: [String] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // Function decl — capture and skip its children (we body-scan separately).
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        summaries.append(makeSummary(from: node))
        return .skipChildren
    }

    // Variable decl — capture identity-shaped statics. Children of function
    // decls are skipped above, so vars inside function bodies never reach
    // here; only top-level vars and vars inside types do.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        captureIdentityCandidates(from: node)
        return .visitChildren
    }

    // Type-bearing decls — emit a TypeDecl AND push/pop the innermost type name.
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .class,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.classKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .struct,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.structKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .enum,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.enumKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .actor,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.actorKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) {
        typeStack.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeText = node.extendedType.trimmedDescription
        typeDecls.append(makeTypeDecl(
            name: extendedTypeText,
            kind: .extension,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.extensionKeyword,
            memberBlock: node.memberBlock
        ))
        typeStack.append(extendedTypeText)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) {
        typeStack.removeLast()
    }

    // Protocol decls — skip body entirely (requirements have no body).
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }

    // MARK: Summary construction

    private func makeSummary(from node: FunctionDeclSyntax) -> FunctionSummary {
        let name = node.name.text
        let parameters = node.signature.parameterClause.parameters.map(makeParameter(from:))
        let returnTypeText = node.signature.returnClause?.type.trimmedDescription
        let effects = node.signature.effectSpecifiers
        let isThrows = effects?.throwsClause != nil
        let isAsync = effects?.asyncSpecifier != nil
        let modifiers = node.modifiers.map { $0.name.text }
        let isMutating = modifiers.contains("mutating")
        let isStatic = modifiers.contains("static") || modifiers.contains("class")

        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )

        let containingTypeName = typeStack.last
        let bodySignals = scanBody(of: node)
        let discoverableGroup = Self.scanDiscoverableGroup(in: node.attributes)

        return FunctionSummary(
            name: name,
            parameters: parameters,
            returnTypeText: returnTypeText,
            isThrows: isThrows,
            isAsync: isAsync,
            isMutating: isMutating,
            isStatic: isStatic,
            location: location,
            containingTypeName: containingTypeName,
            bodySignals: bodySignals,
            discoverableGroup: discoverableGroup
        )
    }

    /// Detect `@Discoverable(group: "...")` on a function decl's
    /// attribute list and return the group string-literal value, or
    /// `nil` when the attribute is absent or carries no `group:`
    /// argument. Recognize-only per PRD v0.4 §5.7 — the attribute is
    /// matched by name (`Discoverable`); SwiftInferProperties does not
    /// take a runtime dependency on `ProtoLawMacro`'s definition.
    /// Multiple `@Discoverable` attributes on the same decl: the first
    /// one wins (Swift compile-time semantics would also flag duplicates,
    /// so this is a conservative tie-break).
    private static func scanDiscoverableGroup(in attributes: AttributeListSyntax) -> String? {
        for element in attributes {
            guard let attribute = element.as(AttributeSyntax.self) else { continue }
            // `attributeName` is a TypeSyntax; trimmedDescription drops
            // surrounding whitespace but preserves the bare identifier.
            // Tolerate fully-qualified `@ProtoLawMacro.Discoverable(...)`
            // by checking the trailing identifier component.
            let nameText = attribute.attributeName.trimmedDescription
            let lastComponent = nameText.split(separator: ".").last.map(String.init) ?? nameText
            guard lastComponent == "Discoverable" else { continue }
            guard case let .argumentList(arguments) = attribute.arguments else { continue }
            for argument in arguments where argument.label?.text == "group" {
                if let group = stringLiteralValue(of: argument.expression) {
                    return group
                }
            }
        }
        return nil
    }

    /// Pull the literal string value out of a single-segment
    /// `StringLiteralExprSyntax`. Returns `nil` for interpolated or
    /// multi-segment literals — interpolation in attribute arguments
    /// would resolve at expansion time and isn't representable as a
    /// stable group name during scan.
    private static func stringLiteralValue(of expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self) else { return nil }
        guard literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }

    private func makeParameter(from syntax: FunctionParameterSyntax) -> Parameter {
        // Swift parameter shapes:
        //   `func f(a: Int)`       → firstName=a, secondName=nil → label=a, name=a
        //   `func f(_ a: Int)`     → firstName=_, secondName=a   → label=nil, name=a
        //   `func f(label a: Int)` → firstName=label, secondName=a → label=label, name=a
        let firstName = syntax.firstName.text
        let secondName = syntax.secondName?.text

        let label: String?
        let internalName: String
        if let secondName {
            label = (firstName == "_") ? nil : firstName
            internalName = secondName
        } else {
            label = firstName
            internalName = firstName
        }

        let rawType = syntax.type.trimmedDescription
        let isInout = rawType.hasPrefix("inout ")
        let typeText = isInout ? String(rawType.dropFirst("inout ".count)) : rawType

        return Parameter(
            label: label,
            internalName: internalName,
            typeText: typeText,
            isInout: isInout
        )
    }

    private func scanBody(of node: FunctionDeclSyntax) -> BodySignals {
        guard let body = node.body else {
            return .empty
        }
        let scanner = BodySignalVisitor(funcName: node.name.text)
        scanner.walk(body)
        return BodySignals(
            hasNonDeterministicCall: !scanner.detectedAPIs.isEmpty,
            hasSelfComposition: scanner.foundSelfComposition,
            nonDeterministicAPIsDetected: scanner.detectedAPIs.sorted(),
            reducerOpsReferenced: scanner.reducerOps.sorted(),
            reducerOpsWithIdentitySeed: scanner.reducerOpsWithIdentitySeed.sorted()
        )
    }

    /// Emit one `IdentityCandidate` per binding inside a static `let` / `var`
    /// whose name is in the curated identity-shaped list AND that has an
    /// explicit type annotation. M2.5 conservative scope skips
    /// type-inferred decls — pairing requires textual type comparison
    /// against `(T, T) -> T` op signatures, and inferring `T` from an
    /// initializer expression isn't tractable without semantic resolution.
    ///
    /// In multi-binding decls (`static let zero, empty: IntSet = .init()`),
    /// SwiftSyntax attaches the type annotation only to the last binding;
    /// earlier bindings inherit it. The loop therefore looks forward to
    /// the next-annotated binding for any unannotated entry.
    private func captureIdentityCandidates(from node: VariableDeclSyntax) {
        let modifiers = node.modifiers.map { $0.name.text }
        guard modifiers.contains("static") || modifiers.contains("class") else {
            return
        }
        let bindings = Array(node.bindings)
        let position = node.bindingSpecifier.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )
        for (index, binding) in bindings.enumerated() {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  let typeText = inheritedTypeText(at: index, in: bindings) else {
                continue
            }
            let name = unescaped(pattern.identifier.text)
            guard IdentityNames.curated.contains(name) else {
                continue
            }
            identities.append(
                IdentityCandidate(
                    name: name,
                    typeText: typeText,
                    containingTypeName: typeStack.last,
                    location: location
                )
            )
        }
    }

    private func inheritedTypeText(
        at index: Int,
        in bindings: [PatternBindingSyntax]
    ) -> String? {
        for forwardIndex in index..<bindings.count {
            if let annotation = bindings[forwardIndex].typeAnnotation {
                return annotation.type.trimmedDescription
            }
        }
        return nil
    }

    /// Build a `TypeDecl` from a type-bearing decl's name, kind,
    /// inheritance clause, introducer keyword, and member block.
    /// Centralizes inheritance-clause parsing, location calculation,
    /// and the M4.1 member-block inspection (stored properties, user-
    /// declared init, user-declared `gen()`) so each `visit(_:)` site
    /// stays a one-liner.
    private func makeTypeDecl(
        name: String,
        kind: TypeDecl.Kind,
        inheritanceClause: InheritanceClauseSyntax?,
        keywordToken: TokenSyntax,
        memberBlock: MemberBlockSyntax
    ) -> TypeDecl {
        let inheritedTypes = inheritanceClause?.inheritedTypes.map {
            $0.type.trimmedDescription
        } ?? []
        let position = keywordToken.positionAfterSkippingLeadingTrivia
        let sourceLocation = converter.location(for: position)
        let location = SourceLocation(
            file: file,
            line: sourceLocation.line,
            column: sourceLocation.column
        )
        // hasUserInit: extensions don't suppress synthesised memberwise
        // init even when they declare an init, so the strategist
        // contract per `DerivationStrategy.swift:147` requires we leave
        // it false for extension records regardless of body content.
        let hasUserInit = (kind == .extension) ? false : Self.scanForUserInit(in: memberBlock)
        // storedMembers: extensions can't add stored properties to a
        // struct (compile error), so always empty for `.extension`.
        let storedMembers = (kind == .extension) ? [] : Self.scanStoredMembers(in: memberBlock)
        return TypeDecl(
            name: name,
            kind: kind,
            inheritedTypes: inheritedTypes,
            location: location,
            hasUserGen: Self.scanForUserGen(in: memberBlock),
            storedMembers: storedMembers,
            hasUserInit: hasUserInit
        )
    }

    /// Stored properties declared in `memberBlock`, in source order.
    /// Returns only `let` / `var` declarations with explicit type
    /// annotations and no accessor block (computed properties skipped).
    /// `static` / `class` properties are also filtered. Multi-binding
    /// lines (`let x: Int, y: Int`) produce one entry per binding.
    /// Ported from SwiftProtocolLaws's `ProtoLawMacroImpl.MemberBlockInspector`
    /// — the macro impl can't be a runtime dep here, so the logic is
    /// duplicated by design (matches the in-tree port the discovery
    /// plugin uses for the same reason).
    private static func scanStoredMembers(in memberBlock: MemberBlockSyntax) -> [StoredMember] {
        var result: [StoredMember] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !isStaticOrClass(varDecl.modifiers) else { continue }
            for binding in varDecl.bindings {
                if binding.accessorBlock != nil { continue }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                guard let typeAnnotation = binding.typeAnnotation else { continue }
                result.append(StoredMember(
                    name: identifier.identifier.text,
                    typeName: typeAnnotation.type.trimmedDescription
                ))
            }
        }
        return result
    }

    /// `true` when `memberBlock` declares any `init(...)`. Used by the
    /// memberwise-Arbitrary derivation gate per the strategist contract.
    private static func scanForUserInit(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members
        where member.decl.as(InitializerDeclSyntax.self) != nil {
            return true
        }
        return false
    }

    /// `true` when `memberBlock` declares a `static func gen(...)` —
    /// the user-supplied generator that wins PRD §5.7's Strategy A
    /// short-circuit. Parameter-list shape isn't checked: the strategist
    /// honours any `static gen` in the body, and emitting a non-zero-arg
    /// `gen()` is a user error the compiler catches.
    private static func scanForUserGen(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard funcDecl.name.text == "gen" else { continue }
            if isStaticOrClass(funcDecl.modifiers) { return true }
        }
        return false
    }

    private static func isStaticOrClass(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
    }

    private func unescaped(_ identifier: String) -> String {
        guard identifier.count >= 2,
              identifier.hasPrefix("`"),
              identifier.hasSuffix("`") else {
            return identifier
        }
        return String(identifier.dropFirst().dropLast())
    }
}
// swiftlint:enable type_body_length

// MARK: - Body signal visitor

private final class BodySignalVisitor: SyntaxVisitor {

    let funcName: String
    var detectedAPIs: Set<String> = []
    var foundSelfComposition = false
    var reducerOps: Set<String> = []
    var reducerOpsWithIdentitySeed: Set<String> = []

    init(funcName: String) {
        self.funcName = funcName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        let calleeText = node.calledExpression.trimmedDescription
        if NonDeterministicAPIs.matches(calleeText) {
            detectedAPIs.insert(calleeText)
        }
        if calleeText == funcName {
            for arg in node.arguments
            where arg.expression.as(FunctionCallExprSyntax.self)?
                .calledExpression
                .trimmedDescription == funcName {
                foundSelfComposition = true
            }
        }
        recordReducerOp(in: node)
        return .visitChildren
    }

    /// Detect `<expr>.reduce(<seed>, <op>)` and `<expr>.reduce(into: <seed>, <op>)`
    /// where `<op>` is a function reference (bare identifier or member-access
    /// `Type.method`). Trailing closures and explicit closure literals are
    /// intentionally skipped — the M2.4 detector only resolves named-function
    /// references, mirroring the conservative-precision posture of §3.5.
    /// M2.5 extends this to additionally classify whether the `<seed>`
    /// argument is identity-shaped (literal zero / empty collection / nil /
    /// false, or a member-access leaf in the curated identity-name list);
    /// that classification feeds the identity-element template's
    /// accumulator-with-empty-seed signal (PRD §5.3, +20).
    private func recordReducerOp(in node: FunctionCallExprSyntax) {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.text == "reduce",
              node.arguments.count == 2 else {
            return
        }
        let seedArg = node.arguments[node.arguments.startIndex]
        let opArg = node.arguments[node.arguments.index(node.arguments.startIndex, offsetBy: 1)]
        let opName: String?
        if let ref = opArg.expression.as(DeclReferenceExprSyntax.self) {
            opName = ref.baseName.text
        } else if let memberRef = opArg.expression.as(MemberAccessExprSyntax.self) {
            opName = memberRef.declName.baseName.text
        } else {
            opName = nil
        }
        guard let opName else {
            return
        }
        reducerOps.insert(opName)
        if isIdentityShapedSeed(seedArg.expression) {
            reducerOpsWithIdentitySeed.insert(opName)
        }
    }

    private func isIdentityShapedSeed(_ expression: ExprSyntax) -> Bool {
        if isIdentityShapedLiteral(expression) {
            return true
        }
        if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
            return IdentityNames.curated.contains(memberAccess.declName.baseName.text)
        }
        return false
    }

    private func isIdentityShapedLiteral(_ expression: ExprSyntax) -> Bool {
        if let int = expression.as(IntegerLiteralExprSyntax.self) {
            return int.literal.text == "0"
        }
        if let float = expression.as(FloatLiteralExprSyntax.self) {
            return float.literal.text == "0.0"
        }
        if let str = expression.as(StringLiteralExprSyntax.self) {
            return isEmptyStringLiteral(str)
        }
        if let array = expression.as(ArrayExprSyntax.self) {
            return array.elements.isEmpty
        }
        if let dict = expression.as(DictionaryExprSyntax.self) {
            return isEmptyDictionaryLiteral(dict)
        }
        if expression.is(NilLiteralExprSyntax.self) {
            return true
        }
        if let bool = expression.as(BooleanLiteralExprSyntax.self) {
            return bool.literal.text == "false"
        }
        return false
    }

    private func isEmptyStringLiteral(_ str: StringLiteralExprSyntax) -> Bool {
        str.segments.allSatisfy { segment in
            guard let plain = segment.as(StringSegmentSyntax.self) else {
                return false
            }
            return plain.content.text.isEmpty
        }
    }

    private func isEmptyDictionaryLiteral(_ dict: DictionaryExprSyntax) -> Bool {
        switch dict.content {
        case .colon:
            return true
        case .elements(let elements):
            return elements.isEmpty
        }
    }
}

// MARK: - Curated identity names (PRD v0.3 §5.2 priority 1)

enum IdentityNames {

    /// Names that signal an identity-shaped value per PRD §5.2's
    /// identity-element priority-1 list. Used both by
    /// `FunctionScannerVisitor.captureIdentityCandidates` (declaration
    /// detection) and by `BodySignalVisitor.isIdentityShapedSeed`
    /// (member-access seed classification, e.g. `xs.reduce(.empty, op)`).
    static let curated: Set<String> = [
        "zero",
        "empty",
        "identity",
        "none",
        "default"
    ]
}

// MARK: - Non-deterministic API list

private enum NonDeterministicAPIs {

    /// Curated callee-text matches. Kept small and explicit for M1.2;
    /// expansion happens as templates encounter false negatives.
    private static let exactMatches: Set<String> = [
        "Date",
        "Date.now",
        "UUID",
        "URLSession.shared",
        "arc4random",
        "arc4random_uniform",
        "drand48",
        "rand",
        "random"
    ]

    /// Callee texts ending in `.random` or `.random(in:)` cover the
    /// `Int.random`, `Double.random(in:)`, `Bool.random()` family without
    /// enumerating every numeric type.
    private static let suffixMatches: [String] = [
        ".random",
        ".random(in:)"
    ]

    static func matches(_ calleeText: String) -> Bool {
        if exactMatches.contains(calleeText) {
            return true
        }
        return suffixMatches.contains { calleeText.hasSuffix($0) }
    }
}
