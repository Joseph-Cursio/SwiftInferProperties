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

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip private / fileprivate — same posture as
        // `FunctionScannerVisitor`. V1.57.A cycle-53 lesson: file-private
        // helpers aren't reachable cross-module and pollute the list.
        let modifiers = node.modifiers.map { $0.name.text }
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

    // Type-stack maintenance — mirrors `FunctionScannerVisitor`.

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ClassDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: StructDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: EnumDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.name.text)
        return .visitChildren
    }
    override func visitPost(_ node: ActorDeclSyntax) { typeStack.removeLast() }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        typeStack.append(node.extendedType.trimmedDescription)
        return .visitChildren
    }
    override func visitPost(_ node: ExtensionDeclSyntax) { typeStack.removeLast() }

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

        let shape: ReducerSignatureShape
        if firstIsInout {
            // Shape 2: `(inout S, A) -> Void`.
            guard returnType == "Void" || returnType.isEmpty else { return nil }
            shape = .inoutStateActionReturnsVoid
        } else if returnType == firstType {
            // Shape 1: `(S, A) -> S`.
            shape = .stateActionReturnsState
        } else if isStateEffectTuple(returnType, expectedFirst: firstType) {
            // Shape 3: `(S, A) -> (S, Effect<A>)`.
            shape = .stateActionReturnsStateAndEffect
        } else {
            return nil
        }

        let position = node.funcKeyword.positionAfterSkippingLeadingTrivia
        let location = converter.location(for: position)
        return ReducerCandidate(
            location: "\(file):\(location.line)",
            enclosingTypeName: typeStack.last,
            functionName: node.name.text,
            signatureShape: shape,
            stateTypeName: firstType,
            actionTypeName: secondType
        )
    }

    /// Does `returnType` look like `(<expectedFirst>, Effect<...>)`?
    /// Tuple-shape match by depth-counting comma split — handles
    /// generic args like `Effect<Action>` and `Effect<S.Action>`
    /// without choking on nested `<>` / `()` / `[]`.
    private func isStateEffectTuple(_ returnType: String, expectedFirst: String) -> Bool {
        guard returnType.hasPrefix("(") && returnType.hasSuffix(")") else { return false }
        let inner = returnType.dropFirst().dropLast()
        var depth = 0
        var commaIdx: String.Index?
        for index in inner.indices {
            let char = inner[index]
            switch char {
            case "<", "(", "[": depth += 1
            case ">", ")", "]": depth -= 1
            case ",":
                if depth == 0 {
                    commaIdx = index
                }
            default:
                break
            }
            if commaIdx != nil { break }
        }
        guard let commaIdx else { return false }
        let firstHalf = inner[..<commaIdx].trimmingCharacters(in: .whitespaces)
        let secondHalf = inner[inner.index(after: commaIdx)...]
            .trimmingCharacters(in: .whitespaces)
        return firstHalf == expectedFirst && secondHalf.hasPrefix("Effect")
    }
}
