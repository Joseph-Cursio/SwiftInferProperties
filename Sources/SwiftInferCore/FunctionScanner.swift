import Foundation
import PropertyLawCore
import SwiftParser
import SwiftSyntax

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
    /// (PRD §16 #6).
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
            typeDecls: visitor.typeDecls,
            restricted: visitor.restricted
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
        let swiftFiles = SwiftSourceFiles.sorted(in: directory)
        var summaries: [FunctionSummary] = []
        var identities: [IdentityCandidate] = []
        var typeDecls: [TypeDecl] = []
        var restricted: [RestrictedFunction] = []
        for fileURL in swiftFiles {
            let corpus = try scanCorpus(file: fileURL)
            summaries.append(contentsOf: corpus.summaries)
            identities.append(contentsOf: corpus.identities)
            typeDecls.append(contentsOf: corpus.typeDecls)
            restricted.append(contentsOf: corpus.restricted)
        }
        return ScannedCorpus(
            summaries: summaries,
            identities: identities,
            typeDecls: typeDecls,
            restricted: restricted
        )
    }
}

// MARK: - Visitor

/// Single-pass AST walker emitting function summaries, identity
/// candidates, and type-decl records. Helpers split across
/// `FunctionScannerVisitor+Summary.swift`,
/// `FunctionScannerVisitor+TypeDecls.swift`, and
/// `FunctionScannerVisitor+Identities.swift`.
final class FunctionScannerVisitor: SyntaxVisitor {

    var summaries: [FunctionSummary] = []
    var identities: [IdentityCandidate] = []
    var typeDecls: [TypeDecl] = []
    /// Functions set aside because no external test could call them, kept with the reason so a
    /// seed that names one can rescue it.
    var restricted: [RestrictedFunction] = []
    let file: String
    let converter: SourceLocationConverter
    var typeStack: [String] = []
    /// Cycle 151 (Lever D) — parallel to `typeStack`: the explicit access modifier on each
    /// enclosing type/extension. Pushed/popped in lockstep.
    ///
    /// **This was a `[Bool]` — "explicitly non-public" — until 2026-08-06, and the missing
    /// distinction was a live defect.** One flag cannot answer two different questions: *is this
    /// surface non-public* (which decides whether it is set aside at all) and *is it invisible to
    /// `@testable import`* (which decides whether widening one member could ever unblock it).
    /// Collapsing them meant a `private` member of a `private` type was reported as
    /// `.notVisibleToTests` — a **widenable** restriction — so `SpeculativeWidening` would snapshot
    /// the package to delete a keyword that exposes nothing, then attribute the resulting silence
    /// to the template catalogue. A second parallel `[Bool]` would have worked and was rejected:
    /// this one already carries a "pushed/popped in lockstep" warning, and two stacks needing the
    /// same discipline is how the pairing drifts.
    var enclosingTypeAccess: [EnclosingTypeAccess] = []

    init(file: String, converter: SourceLocationConverter) {
        self.file = file
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        // V1.57.A (cycle 54) — skip `private` / `fileprivate` helpers, which
        // can't be property-tested cross-module (cycles 53/54 — findings
        // pruned from the tree; read them at `31a347a`).
        //
        // Cycle 148 (Lever A) — also skip the other non-public / SPI shapes an
        // external verifier can never call. Pre-148 they were indexed and only
        // failed at verify time as `architectural-coverage-pending`
        // (`unsupported-carrier` on `_`-types, `internal-api-not-accessible`),
        // inflating the v1 algebraic measured-execution denominator with
        // false positives. Per PRD §3.5 (high precision, fewer suggestions)
        // they shouldn't be surfaced at all. Three signals:
        //   - explicit `internal` modifier (e.g. swift-numerics'
        //     `internal static func rescaledDivide`, swift-collections'
        //     `internal mutating func _ensureUnique`). SAFE — Swift's default
        //     access carries NO token, so internal-BY-default user code (incl.
        //     our test fixtures) is untouched; only deliberately-marked
        //     internal SPI is dropped. (Reverses cycle-54's "keep + handle at
        //     verify": an externally-uncallable symbol is noise, not a
        //     deferred verdict.) NB: the access modifier — NOT the `_` prefix —
        //     is the reliable signal: `public static func _relaxedAdd` is an
        //     underscore-named PUBLIC SPI that genuinely verifies (measured),
        //     so a `_`-name filter would wrongly drop it.
        //   - `_`-prefixed enclosing type / extension (e.g. `_HashTable`,
        //     `_UnsafeHashTable`) — the carrier itself is a private stdlib
        //     internal; no measured pick has a `_`-prefixed carrier.
        //
        // Cycle 151 (Lever D) — three more non-API shapes that survived to
        // verify as `architectural-coverage-pending` false positives (the
        // last 9 of the v1 algebraic corpus):
        //   - `@_spi(...)` declarations (e.g. swift-collections'
        //     `@_spi(Testing) public static func _minimumCapacity`) — SPI is
        //     "less public than public" test/tooling surface, not real API. An
        //     external verifier can't import the SPI. Distinct from the plain
        //     `public _relaxedAdd` Lever A deliberately keeps.
        //   - nested LOCAL functions (e.g. swift-algorithms' `binomial(n:k:)`
        //     declared inside the `count` computed property) — reached only via
        //     a property/closure body, never a callable API member.
        //   - an explicitly non-public ENCLOSING TYPE (e.g. SwiftPropertyLaws'
        //     `internal enum ViolationFormatter`) — its members are
        //     externally uncallable even when the member itself carries no
        //     modifier. Extends the explicit-`internal` function rule to the
        //     type level. SAFE — internal-BY-default types (our fixtures) carry
        //     no token, so they're untouched; only deliberately-marked types.
        //
        // Cycle A2 — the *reason* is now kept rather than thrown away. Discovery is unchanged:
        // these never enter `summaries`, so no unseeded run surfaces them and the precision the
        // cycles above bought is intact. But a **seed** naming one of them is an explicit request
        // from a producer that has already examined the function, and silently overruling an
        // explicit request is not precision — it is a confident zero. The calibration above was
        // measured on library corpora, where `private` really is an implementation detail; an app
        // has no public API at all, and its pure logic lives almost entirely in `private` helpers
        // inside views and view models. Dropping them without a word is what left the tool with
        // nothing to say about application code.
        if let restriction = accessRestriction(of: node) {
            restricted.append(
                RestrictedFunction(summary: makeSummary(from: node), restriction: restriction)
            )
            return .skipChildren
        }
        summaries.append(makeSummary(from: node))
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        captureIdentityCandidates(from: node)
        // Recall-widening epic #1 — a read-only computed property is a nullary
        // `self -> T` map, so surface it as a summary (the involution template's
        // instance shape). Skip non-public / SPI properties on the same basis as
        // functions: an external test can't reach them.
        if let summary = makeSummary(fromComputedProperty: node) {
            if let restriction = accessRestriction(ofVariable: node) {
                restricted.append(RestrictedFunction(summary: summary, restriction: restriction))
            } else {
                summaries.append(summary)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .class,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.classKeyword,
            memberBlock: node.memberBlock, genericParameterClause: node.genericParameterClause
        ))
        typeStack.append(node.name.text)
        enclosingTypeAccess.append(Self.access(of: node.modifiers))
        return .visitChildren
    }
    override func visitPost(_: ClassDeclSyntax) {
        typeStack.removeLast()
        enclosingTypeAccess.removeLast()
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .struct,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.structKeyword,
            memberBlock: node.memberBlock, genericParameterClause: node.genericParameterClause
        ))
        typeStack.append(node.name.text)
        enclosingTypeAccess.append(Self.access(of: node.modifiers))
        return .visitChildren
    }
    override func visitPost(_: StructDeclSyntax) {
        typeStack.removeLast()
        enclosingTypeAccess.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .enum,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.enumKeyword,
            memberBlock: node.memberBlock, genericParameterClause: node.genericParameterClause
        ))
        typeStack.append(node.name.text)
        enclosingTypeAccess.append(Self.access(of: node.modifiers))
        return .visitChildren
    }
    override func visitPost(_: EnumDeclSyntax) {
        typeStack.removeLast()
        enclosingTypeAccess.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .actor,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.actorKeyword,
            memberBlock: node.memberBlock, genericParameterClause: node.genericParameterClause
        ))
        typeStack.append(node.name.text)
        enclosingTypeAccess.append(Self.access(of: node.modifiers))
        return .visitChildren
    }
    override func visitPost(_: ActorDeclSyntax) {
        typeStack.removeLast()
        enclosingTypeAccess.removeLast()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let extendedTypeText = node.extendedType.trimmedDescription
        typeDecls.append(makeTypeDecl(
            name: extendedTypeText,
            kind: .extension,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.extensionKeyword,
            memberBlock: node.memberBlock, isConditionalExtension: node.genericWhereClause != nil
        ))
        typeStack.append(extendedTypeText)
        enclosingTypeAccess.append(Self.access(of: node.modifiers))
        return .visitChildren
    }
    override func visitPost(_: ExtensionDeclSyntax) {
        typeStack.removeLast()
        enclosingTypeAccess.removeLast()
    }

    /// Protocol decls — **record the declaration, skip the body**.
    ///
    /// The body skip is unchanged and still correct: requirements have no implementations,
    /// so there is nothing to summarise, and Swift forbids nesting a concrete type inside a
    /// protocol, so `.skipChildren` cannot lose one.
    ///
    /// What changed (2026-07-30) is that the decl itself is now recorded, for its
    /// **inheritance clause**. Skipping the node outright meant a protocol's refinements were
    /// never seen by anything: `ProtocolCoverageMap` could not learn that `BinaryInteger`
    /// refines `Strideable` (`Integers.swift:533`), so **no coverage veto could fire on any
    /// protocol-extension carrier** — a whole mechanism disabled for a whole class of carrier,
    /// not a `Strideable`-specific gap. Measured before: 6 typeDecls named `BinaryInteger` on
    /// `stdlib/public/core`, every one with `inheritedTypes == []`.
    ///
    /// A protocol record is inert everywhere else by construction. It carries no stored
    /// members, no initialisers and no enum cases, and
    /// `TypeShape.Kind.init?(swiftInferKind:)` maps `.protocol` to `nil`, so protocols never
    /// reach the strategist or become generator targets — the same treatment `.extension`
    /// already gets.
    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        typeDecls.append(makeTypeDecl(
            name: node.name.text,
            kind: .protocol,
            inheritanceClause: node.inheritanceClause,
            keywordToken: node.protocolKeyword,
            memberBlock: node.memberBlock
        ))
        return .skipChildren
    }
}
