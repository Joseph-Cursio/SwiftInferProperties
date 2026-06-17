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
        let visitor = ReducerDiscoveryVisitor(file: file, converter: converter)
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
///
/// `internal` (not `private`) so the TCA-conformance walk can live in
/// `ReducerDiscoverer+TCAWalk.swift` — file-split to keep this file under
/// SwiftLint's `file_length` cap (cycle 109). Only referenced from
/// `ReducerDiscoverer.discover`.
final class ReducerDiscoveryVisitor: SyntaxVisitor {

    var candidates: [ReducerCandidate] = []
    let file: String
    let converter: SourceLocationConverter
    var typeStack: [String] = []
    /// Cycle 109 — parallel to `typeStack`: for each enclosing type
    /// currently on the stack, the set of type names it declares as
    /// **nested** members (`struct`/`enum`/`class`/`actor`/`typealias`).
    /// `matchReducer` consults `.last` to decide whether a bare
    /// `State`/`Action` param type is nested in the enclosing type (and
    /// must be pre-qualified to `<Enclosing>.State` for stub emission —
    /// fixing cycle-108 Blocker A) versus a top-level type referenced by
    /// bare name (left unqualified). Pushed/popped in lockstep with
    /// `typeStack` in every type-decl `visit` / `visitPost`.
    var nestedTypeNamesStack: [Set<String>] = []
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
        pushType(node.name.text, memberBlock: node.memberBlock)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: node.name.text
        )
        return .visitChildren
    }
    override func visitPost(_: ClassDeclSyntax) { popType() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text, memberBlock: node.memberBlock)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: node.name.text
        )
        return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) { popType() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text, memberBlock: node.memberBlock)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: node.name.text
        )
        return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) { popType() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        pushType(node.name.text, memberBlock: node.memberBlock)
        return .visitChildren
    }
    override func visitPost(_: ActorDeclSyntax) { popType() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeName = node.extendedType.trimmedDescription
        pushType(extendedTypeName, memberBlock: node.memberBlock)
        extractTCACandidatesIfReducerConformer(
            attributes: node.attributes,
            modifiers: node.modifiers,
            inheritanceClause: node.inheritanceClause,
            memberBlock: node.memberBlock,
            enclosingTypeName: extendedTypeName
        )
        return .visitChildren
    }
    override func visitPost(_: ExtensionDeclSyntax) { popType() }

    // MARK: - Type-stack push/pop (Cycle 109 — tracks nested type names)

    /// Push a type onto `typeStack` and record its directly-nested type
    /// names on `nestedTypeNamesStack` in lockstep. Both stacks are
    /// popped together in `popType()`. The nested-name collection +
    /// qualification helpers live in `+ShapeHelpers.swift`.
    private func pushType(_ name: String, memberBlock: MemberBlockSyntax) {
        typeStack.append(name)
        nestedTypeNamesStack.append(ReducerDiscoverer.nestedTypeNames(in: memberBlock))
    }

    private func popType() {
        typeStack.removeLast()
        nestedTypeNamesStack.removeLast()
    }

    // MARK: - Signature match

    /// Try to match `node` against one of the three canonical reducer
    /// signature shapes. Returns `nil` if no shape matches — including
    /// all the deliberate-skip cases (wrong arity, return-type
    /// mismatch, etc.).
    private func matchReducer(in node: FunctionDeclSyntax) -> ReducerCandidate? {
        // Workflow (Square): `apply(toState: inout State[, context:])` —
        // Action is the enclosing type (Self), matched before the arity-2
        // guard (v3 arity-1 + v4/v5 `context:` forms); free `apply` skipped.
        if let workflow = ReducerDiscoverer.classifyWorkflowApply(node: node),
            let actionType = typeStack.last {
            return makeCandidate(
                node: node, stateType: workflow.state, actionType: actionType,
                shape: workflow.shape, carrierKind: .workflow
            )
        }

        let parameters = node.signature.parameterClause.parameters
        guard parameters.count == 2 else { return nil }

        let first = parameters[parameters.startIndex]
        let second = parameters[parameters.index(after: parameters.startIndex)]
        let firstRaw = first.type.trimmedDescription
        let secondRaw = second.type.trimmedDescription
        let returnRaw = node.signature.returnClause?.type.trimmedDescription ?? "Void"
        let returnType = returnRaw.trimmingCharacters(in: .whitespaces)

        // ReSwift `(Action, State?) -> State` — Action-first, Optional
        // incoming State. Reversed order can't go through `classifyShape`;
        // matched + un-reversed here, mapped to `.stateActionReturnsState`.
        if let reSwift = ReducerDiscoverer.classifyReSwift(
            firstRaw: firstRaw, secondRaw: secondRaw, returnType: returnType
        ) {
            return makeCandidate(
                node: node, stateType: reSwift.state, actionType: reSwift.action,
                shape: .stateActionReturnsState, carrierKind: .reSwift
            )
        }

        // Canonical `(State, Action)` order. Strip `inout ` on the State
        // param; reject `inout` on the Action param (none of the canonical
        // shapes carry it — keeps the §2.3 strict-Action posture).
        let firstIsInout = firstRaw.hasPrefix("inout ")
        let firstType = firstIsInout
            ? String(firstRaw.dropFirst("inout ".count)).trimmingCharacters(in: .whitespaces)
            : firstRaw
        if secondRaw.hasPrefix("inout ") { return nil }
        let secondType = secondRaw

        guard let shape = Self.classifyShape(
            firstType: firstType,
            firstIsInout: firstIsInout,
            returnType: returnType
        ) else {
            return nil
        }

        // V1.92 (cycle-89 fix for cycle-87 finding #1) — two-scalar
        // false-positive filter. `transform(_: Int, _: Int) -> Int` and
        // friends match `(S, A) -> S` structurally with S = A = Int, but
        // no plausible reducer has scalar State + scalar Action. PRD §3.5.
        if ReducerDiscoverer.isScalarTypeName(firstType), ReducerDiscoverer.isScalarTypeName(secondType) {
            return nil
        }

        // V1.C — `.elmStyle` is a free `(S, A) -> S`. Mobius is the
        // canonical-order `(S, A) -> Next<S, E>` (recognized as the
        // effect-bearing shape, distinguished from the `(S, Effect)` tuple
        // by the `Next<…>` return). Everything else stays `.generic`.
        let carrierKind = classifyCanonicalCarrier(
            shape: shape, returnType: returnType, stateType: firstType
        )
        return makeCandidate(
            node: node, stateType: firstType, actionType: secondType,
            shape: shape, carrierKind: carrierKind
        )
    }

    /// `.mobius` for an effect-bearing `Next<S, E>` return; `.elmStyle`
    /// for a free `(S, A) -> S`; `.generic` otherwise.
    private func classifyCanonicalCarrier(
        shape: ReducerSignatureShape,
        returnType: String,
        stateType: String
    ) -> ReducerCarrierKind {
        if shape == .stateActionReturnsStateAndEffect,
            ReducerDiscoverer.looksLikeMobiusNext(returnType, expectedFirst: stateType) {
            return .mobius
        }
        if typeStack.last == nil, shape == .stateActionReturnsState {
            return .elmStyle
        }
        return .generic
    }

    /// Build a `ReducerCandidate`, qualifying nested State/Action names to
    /// `<Enclosing>.Name` (cycle-108 Blocker A). Shared by all match paths.
    private func makeCandidate(
        node: FunctionDeclSyntax,
        stateType: String,
        actionType: String,
        shape: ReducerSignatureShape,
        carrierKind: ReducerCarrierKind
    ) -> ReducerCandidate {
        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        let enclosingTypeName = typeStack.last
        let purity = ReducerPurityAnalyzer.analyze(node)
        let nested = nestedTypeNamesStack.last ?? []
        return ReducerCandidate(
            location: "\(file):\(location.line)",
            enclosingTypeName: enclosingTypeName,
            functionName: node.name.text,
            signatureShape: shape,
            stateTypeName: ReducerDiscoverer.qualifyIfNested(stateType, enclosing: enclosingTypeName, nested: nested),
            actionTypeName: ReducerDiscoverer.qualifyIfNested(actionType, enclosing: enclosingTypeName, nested: nested),
            carrierKind: carrierKind,
            purity: purity
        )
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
        if ReducerDiscoverer.looksLikeMobiusNext(returnType, expectedFirst: firstType) {
            // Mobius: `(S, A) -> Next<S, E>` — same effect-bearing shape as
            // the tuple form (the new State + discarded effects), mapped
            // onto the same case. `matchReducer` re-checks the `Next<…>`
            // return to label the carrier `.mobius`.
            return .stateActionReturnsStateAndEffect
        }
        return nil
    }
}
