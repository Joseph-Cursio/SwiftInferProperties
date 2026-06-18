import Foundation

/// PROTOTYPE (SwiftSyntax lint-rule visitor carrier) — one detected
/// `SyntaxVisitor` subclass that accumulates findings as it walks an AST.
/// Recognised structurally: a `class` declaring at least one
/// `visit(_:) -> SyntaxVisitorContinueKind` override (the unmistakable
/// SwiftSyntax visitor signal — no other method has that return type).
/// Modelled as an issue-accumulator carrier:
///
///   | Carrier slot      | Rule visitor                                  |
///   |-------------------|-----------------------------------------------|
///   | input             | a parsed `SourceFileSyntax` (walked)          |
///   | output / State    | the accumulated findings (`detectedIssues`)   |
///   | step              | each `visit(node)` callback emitting a finding|
///
/// **Slice 1 (this type) is recognition only.** It captures enough to list
/// the carrier for a human — location, the inherited base/conformance, the
/// syntax-node types it visits, and the rule identifiers it emits — and
/// deliberately emits **no** invariant. The carrier's only *generic* law is
/// detection determinism (`detect(s) == detect(s)`), which is near-trivially
/// true on a pure AST walk and would flood the `.possible` tier across every
/// visitor (the Daikon trap the PRD warns against). Its one high-value law —
/// no false positive on pattern-free input — is per-rule, not generic, and
/// is TestLifter territory. See `docs/rule-visitor-carrier-scoping.md` for
/// the full fork analysis and why verify is shelved.
public struct RuleVisitorCandidate: Sendable, Equatable {

    /// `<path>:<line>` of the class declaration — same click-target UX as
    /// `ReducerCandidate.location` / `ViewModelCandidate.location`.
    public let location: String

    /// The visitor class name (`"ForceUnwrapVisitor"`).
    public let typeName: String

    /// The inherited types / conformances from the class declaration's
    /// inheritance clause, in source order (`["BasePatternVisitor"]`, or
    /// `["SyntaxVisitor", "SomeProtocol"]` for a direct subclass). Surfaced
    /// so a human can see which base the carrier rides.
    public let inheritedTypes: [String]

    /// The SwiftSyntax node types this visitor overrides `visit(_:)` for
    /// (`["ForceUnwrapExprSyntax"]`), sorted + deduplicated. These are the
    /// AST shapes the rule inspects — the "alphabet" of its detection.
    public let visitedNodeTypes: [String]

    /// The rule identifiers passed as a `ruleName:` argument to issue-emitting
    /// calls in the visitor's bodies (`["forceUnwrap"]`), sorted + deduped,
    /// with any leading `.` stripped (`.forceUnwrap` → `"forceUnwrap"`). Empty
    /// when the visitor emits findings without a `ruleName:` label.
    public let emittedRuleNames: [String]

    public init(
        location: String,
        typeName: String,
        inheritedTypes: [String],
        visitedNodeTypes: [String],
        emittedRuleNames: [String]
    ) {
        self.location = location
        self.typeName = typeName
        self.inheritedTypes = inheritedTypes
        self.visitedNodeTypes = visitedNodeTypes
        self.emittedRuleNames = emittedRuleNames
    }
}
