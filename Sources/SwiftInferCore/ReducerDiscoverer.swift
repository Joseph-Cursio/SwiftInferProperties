import Foundation
import SwiftParser
import SwiftSyntax

/// V2.0 M1.A — SwiftSyntax pass that detects reducer-shaped functions
/// from their signature only. The output of `ReducerDiscoverer` is the
/// input for every later v2.0 milestone — M2's Action-sequence
/// generators key on the candidate's `actionTypeName`, M3's in-process
/// verify wraps the candidate's signature shape, and M4–M7's
/// interaction-template scoring runs against the candidate's State /
/// Action types.
///
/// **Three canonical shapes** matched textually (PRD §6.2):
///
///   - `(S, A) -> S` — Elm-style, hand-rolled, free-function reducers.
///   - `(inout S, A) -> Void` — common in TCA `Reduce` closures and
///     hand-rolled reducers.
///   - `(S, A) -> (S, Effect<A>)` — TCA pre-2022, ReSwift with thunks.
///     `Effect<...>` is matched by **name prefix only** — no type
///     resolution into `import` statements. Cross-import correctness
///     is the caller's responsibility (false matches surface in
///     calibration and are why §3.5 mandates default-`Possible`
///     visibility on every new template family).
///
/// **What M1.A skips, on purpose:**
///   - **Generic functions** (`func reduce<S, A>(...)`) — the type-name
///     extraction gets weird with generic placeholders; deferred to a
///     later milestone if calibration shows it matters.
///   - **`private` / `fileprivate` functions** — mirrors V1.57.A's
///     cycle-53 lesson: file-private helpers aren't reachable across
///     modules and pollute the candidate list. (Note: matches
///     `FunctionScannerVisitor`'s posture in `FunctionScanner.swift:134`.)
///   - **Nested functions** (declared inside another function's body) —
///     rare in idiomatic Swift, and including them conflates the
///     scan with the outer function's signals. Same posture as
///     `FunctionScanner`.
///   - **Single-parameter `dispatch(_:)` shape** — cleanly rejected by
///     the arity-2 check, which implements PRD §2.3's
///     "implicit-action surface out of scope" without special-casing.
///   - **TCA `var body: some ReducerOf<Self>`** — the body's closure
///     shape isn't a `FunctionDeclSyntax` at all; recovering reducers
///     from TCA conformance walks is the M1.B deliverable.
///
/// Architecturally a near-clone of `FunctionScanner`'s shape — single
/// public namespace with `discover(source:file:)`, `discover(file:)`,
/// `discover(directory:)` entries plus an internal `Visitor` class
/// that walks the tree once.
public enum ReducerDiscoverer {

    /// Scan a single in-memory source string. `file` is the label
    /// attached to every emitted candidate's `location` — pass the
    /// path you want shown to the user.
    public static func discover(source: String, file: String) -> [ReducerCandidate] {
        let tree = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: file, tree: tree)
        let visitor = Visitor(file: file, converter: converter)
        visitor.walk(tree)
        return visitor.candidates
    }

    /// Scan a single `.swift` file on disk. Reads as UTF-8.
    public static func discover(file: URL) throws -> [ReducerCandidate] {
        let source = try String(contentsOf: file, encoding: .utf8)
        return discover(source: source, file: file.path)
    }

    /// Recursively scan every `.swift` file under `directory`. Files
    /// are visited in deterministic (sorted-path) order so the merged
    /// candidate list is stable across runs — matches v1's
    /// byte-identical-reproducibility posture (PRD §16 #6 carried
    /// from v1.0).
    public static func discover(directory: URL) throws -> [ReducerCandidate] {
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
        var candidates: [ReducerCandidate] = []
        for fileURL in swiftFiles {
            candidates.append(contentsOf: try discover(file: fileURL))
        }
        return candidates
    }
}

// MARK: - Visitor

/// Single-pass AST walker emitting `ReducerCandidate` records. Tracks
/// the enclosing-type stack so `enclosingTypeName` is set correctly
/// for methods inside `struct` / `class` / `enum` / `actor` /
/// `extension` blocks — same convention as `FunctionScannerVisitor`.
private final class Visitor: SyntaxVisitor {

    var candidates: [ReducerCandidate] = []
    let file: String
    let converter: SourceLocationConverter
    var typeStack: [String] = []
    /// V1.B — set when the file imports `ComposableArchitecture`. The
    /// TCA conformance walk only fires under this flag (PRD §6.3
    /// step 1 — same name-match strategy v1 uses for `@Discoverable`,
    /// avoids false matches against unrelated `Reducer` protocols).
    var importsComposableArchitecture: Bool = false

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Imports

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.path.trimmedDescription == "ComposableArchitecture" {
            importsComposableArchitecture = true
        }
        return .skipChildren
    }

    // MARK: - Function-decl signature scan (M1.A path)

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip private / fileprivate — same posture as
        // `FunctionScannerVisitor`. V1.57.A cycle-53 lesson: file-private
        // helpers aren't reachable cross-module and pollute the list.
        let modifiers = node.modifiers.map(\.name.text)
        if modifiers.contains("private") || modifiers.contains("fileprivate") {
            return .skipChildren
        }
        // Skip generic functions — type-name extraction gets weird with
        // generic placeholders. Calibrate the deferral later.
        if node.genericParameterClause != nil {
            return .skipChildren
        }
        if let candidate = matchReducer(in: node) {
            candidates.append(candidate)
        }
        return .skipChildren
    }

    // MARK: - Type-stack maintenance + TCA conformance walk

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: node.name.text
        )
        return .visitChildren
    }
    override func visitPost(_: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: node.name.text
        )
        return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: node.name.text
        )
        return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_: ActorDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeName = node.extendedType.trimmedDescription
        typeStack.append(extendedTypeName)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: extendedTypeName
        )
        return .visitChildren
    }
    override func visitPost(_: ExtensionDeclSyntax) { typeStack.removeLast() }

    // MARK: - Signature match

    /// Try to match `node` against one of the three canonical reducer
    /// signature shapes. Returns `nil` if no shape matches — including
    /// all the deliberate-skip cases (wrong arity, return-type
    /// mismatch, etc.).
    private func matchReducer(in node: FunctionDeclSyntax) -> ReducerCandidate? {
        let parameters = node.signature.parameterClause.parameters
        guard parameters.count == 2 else { return nil }

        let first = parameters[parameters.startIndex]
        let second = parameters[parameters.index(after: parameters.startIndex)]
        let firstRaw = first.type.trimmedDescription
        let secondRaw = second.type.trimmedDescription

        // Strip `inout ` prefix on each param's type.
        let firstIsInout = firstRaw.hasPrefix("inout ")
        let firstType = firstIsInout
            ? String(firstRaw.dropFirst("inout ".count)).trimmingCharacters(in: .whitespaces)
            : firstRaw
        // Reject `inout` on the Action parameter — none of the
        // canonical shapes have it there, and accepting it would
        // muddy the §2.3 strict-Action-surface posture.
        if secondRaw.hasPrefix("inout ") { return nil }
        let secondType = secondRaw

        let returnRaw = node.signature.returnClause?.type.trimmedDescription ?? "Void"
        let returnType = returnRaw.trimmingCharacters(in: .whitespaces)
        guard let shape = Self.classifyShape(
            firstType: firstType,
            firstIsInout: firstIsInout,
            returnType: returnType
        ) else {
            return nil
        }

        // V1.92 (cycle-89 fix for cycle-87 finding #1) — two-scalar
        // false-positive filter. `transform(_: Int, _: Int) -> Int`
        // and friends match `(S, A) -> S` structurally with S = A =
        // Int, but no plausible reducer has scalar State + scalar
        // Action. Reject when both types are in the curated scalar
        // set. PRD §3.5 conservative-inference posture.
        if ReducerDiscoverer.isScalarTypeName(firstType), ReducerDiscoverer.isScalarTypeName(secondType) {
            return nil
        }

        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        let enclosingTypeName = typeStack.last
        // V1.C — `.elmStyle` differentiation. A free `(S, A) -> S`
        // reducer (the Elm idiom — `func update(_:_:)` at module
        // scope) is the canonical carrier of that label. Methods on a
        // type, and the two `inout` / tuple-return shapes when free,
        // stay `.generic` — they're not the Elm convention even if
        // signature-matched.
        let carrierKind: ReducerCarrierKind
        if enclosingTypeName == nil, shape == .stateActionReturnsState {
            carrierKind = .elmStyle
        } else {
            carrierKind = .generic
        }
        // M8.B — classify the body's purity for the §7 routing
        // signal: `.hiddenMutability` is suppressed at verify time;
        // `.pure` + `.effectBearing` both flow through M3.E (the
        // emit shape differs per signature, not per body).
        let purity = ReducerPurityAnalyzer.analyze(node)
        return ReducerCandidate(
            location: "\(file):\(location.line)",
            enclosingTypeName: enclosingTypeName,
            functionName: node.name.text,
            signatureShape: shape,
            stateTypeName: firstType,
            actionTypeName: secondType,
            carrierKind: carrierKind,
            purity: purity
        )
    }

    // MARK: - TCA conformance walk (V1.B)

    /// V1.B + V1.D — entry point for the TCA path. Fires when the
    /// file imports `ComposableArchitecture` AND **either** the
    /// declaration's inheritance clause names `Reducer` (V1.B
    /// pre-macro form: `struct Foo: Reducer`) **or** the declaration
    /// has the `@Reducer` macro attribute (V1.D modern form,
    /// dominant since TCA 1.0+ — `@Reducer struct Foo`). Private /
    /// fileprivate types are skipped, matching the function-scan
    /// posture. The body walk is idempotent for a single decl, so
    /// a type with both forms (`@Reducer struct Foo: Reducer`)
    /// emits one set of candidates, not two.
    private func extractTCACandidatesIfReducerConformer(
        attributes: AttributeListSyntax,
        modifiers: DeclModifierListSyntax,
        inheritanceClause: InheritanceClauseSyntax?,
        memberBlock: MemberBlockSyntax,
        enclosingTypeName: String
    ) {
        guard importsComposableArchitecture else { return }
        let viaConformance = Self.declaresReducerConformance(inheritanceClause)
        let viaMacro = ReducerDiscoverer.hasReducerAttribute(attributes)
        guard viaConformance || viaMacro else { return }
        let modifierNames = modifiers.map(\.name.text)
        if modifierNames.contains("private") || modifierNames.contains("fileprivate") {
            return
        }
        extractTCACandidates(from: memberBlock, enclosingTypeName: enclosingTypeName)
    }

    /// Does an inheritance clause name TCA's `Reducer` protocol?
    /// Matches the literal `Reducer` plus `Reducer<...>` and
    /// `ReducerOf<...>` generic variants. Static so test fixtures can
    /// drive it without spinning up a full walk.
    static func declaresReducerConformance(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        for inherited in clause.inheritedTypes {
            let text = inherited.type.trimmedDescription
            if text == "Reducer" || text.hasPrefix("Reducer<") || text.hasPrefix("ReducerOf<") {
                return true
            }
        }
        return false
    }

    /// Find `var body` and walk its initializer / accessor block for
    /// `Reduce { state, action in ... }` calls.
    private func extractTCACandidates(
        from memberBlock: MemberBlockSyntax,
        enclosingTypeName: String
    ) {
        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in variable.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      identifier.identifier.text == "body" else { continue }
                if let initializer = binding.initializer?.value {
                    walkForReduceClosures(in: Syntax(initializer), enclosingTypeName: enclosingTypeName)
                }
                if let accessor = binding.accessorBlock {
                    walkForReduceClosures(in: Syntax(accessor), enclosingTypeName: enclosingTypeName)
                }
            }
        }
    }

    /// Recursively walk `subtree` looking for `Reduce { ... }` calls
    /// with an arity-2 trailing closure. Each match emits one
    /// `ReducerCandidate`. Composed reducers (`Scope`, `BindingReducer`,
    /// `CombineReducers`, `EmptyReducer`, etc.) are walked past — only
    /// `Reduce` introduces the closure shape M1.B is after.
    private func walkForReduceClosures(in subtree: Syntax, enclosingTypeName: String) {
        let walker = ReduceClosureWalker(
            file: file,
            converter: converter,
            enclosingTypeName: enclosingTypeName
        )
        walker.walk(subtree)
        candidates.append(contentsOf: walker.candidates)
    }

    // MARK: - Tuple-return helper (M1.A)

    /// V1.92 lint pass — shape classification extracted from
    /// `matchReducer` so the outer function stays under SwiftLint's
    /// 50-line cap. Returns the matched `ReducerSignatureShape` or
    /// `nil` when no canonical shape matches.
    static func classifyShape(
        firstType: String,
        firstIsInout: Bool,
        returnType: String
    ) -> ReducerSignatureShape? {
        if firstIsInout {
            if returnType == "Void" || returnType.isEmpty {
                return .inoutStateActionReturnsVoid
            }
            if ReducerDiscoverer.looksLikeEffect(returnType) {
                // V1.92 — Shape 4: `(inout S, A) -> Effect<A>`.
                return .inoutStateActionReturnsEffect
            }
            return nil
        }
        if returnType == firstType {
            // Shape 1: `(S, A) -> S`.
            return .stateActionReturnsState
        }
        if ReducerDiscoverer.isStateEffectTuple(returnType, expectedFirst: firstType) {
            // Shape 3: `(S, A) -> (S, Effect<A>)`.
            return .stateActionReturnsStateAndEffect
        }
        return nil
    }
}
