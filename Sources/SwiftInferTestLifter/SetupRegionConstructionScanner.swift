import SwiftSyntax

/// TestLifter M4.1 — corpus-wide aggregation of `T(...)` constructor
/// expressions found across every test method body.
///
/// Walks every method body in `[TestMethodSummary]` looking for
/// `FunctionCallExpr`s whose called expression is a bare type-shaped
/// identifier (`Doc(...)`, `Author()`, etc. — same UpperCamelCase
/// recognition rule M4.0's `SetupRegionTypeAnnotationScanner` uses for
/// bare-constructor bindings). Each match contributes one *site* to a
/// per-`(typeName, shape)` accumulator; the M4.3 `MockGeneratorSynthesizer`
/// then queries the accumulator to find types with `siteCount ≥ 3`
/// that have a single dominant shape (the §13 mock-synthesis bar).
///
/// **Argument-shape fingerprinting** treats labels as a set, not a list.
/// `Doc(title: "x", count: 3)` and `Doc(count: 5, title: "y")` collapse
/// to the same shape via stable label-then-kind sort at fingerprint
/// time. `Doc(title:)` and `Doc(title:author:)` produce two distinct
/// shapes (different label *sets*) and therefore two distinct entries
/// in the record. Constructor calls with non-literal arguments
/// (`Doc(title: makeName())`) are skipped — the mock synthesizer needs
/// fingerprintable kinds, and `makeName()` is opaque.
///
/// **Pure function** over its inputs. No FunctionSummary lookup, no
/// semantic resolution, no I/O. The §13 perf budget for record
/// construction is < 100ms on the synthetic 100-test-file corpus
/// (one extra SyntaxVisitor pass per body, linear in body size).
public enum SetupRegionConstructionScanner {

    /// Build a `ConstructionRecord` aggregating every `T(...)` call
    /// site found across the supplied test methods. Order-independent —
    /// the same set of test methods produces the same record entries
    /// (the entries' internal `observedLiterals` rows preserve
    /// per-site visit order, but the entry list itself is sorted by
    /// `(typeName, sortedLabels)` for stability).
    public static func record(over methods: [TestMethodSummary]) -> ConstructionRecord {
        var accumulator: [Key: Bucket] = [:]
        for method in methods {
            let visitor = ConstructionVisitor(viewMode: .sourceAccurate)
            visitor.walk(method.body)
            for site in visitor.sites {
                let key = Key(typeName: site.typeName, shape: site.shape)
                if accumulator[key] == nil {
                    accumulator[key] = Bucket(shape: site.shape, sites: [])
                }
                accumulator[key]?.sites.append(site.literals)
            }
        }
        let entries = accumulator
            .map { key, bucket in
                ConstructionRecordEntry(
                    typeName: key.typeName,
                    shape: bucket.shape,
                    siteCount: bucket.sites.count,
                    observedLiterals: bucket.sites
                )
            }
            .sorted { lhs, rhs in
                if lhs.typeName != rhs.typeName {
                    return lhs.typeName < rhs.typeName
                }
                return lhs.shape.canonicalLabelKey < rhs.shape.canonicalLabelKey
            }
        return ConstructionRecord(entries: entries)
    }

    private struct Key: Hashable {
        let typeName: String
        let shape: ConstructionShape
    }

    private struct Bucket {
        let shape: ConstructionShape
        var sites: [[String]]
    }
}

// MARK: - Public types

/// Argument-shape fingerprint for one constructor call. Label-order-
/// independent — `Doc(title:count:)` and `Doc(count:title:)` produce
/// the same `ConstructionShape` after the canonical label-then-kind
/// sort. Positional (unlabeled) arguments preserve their `nil` label
/// and sort to the front of the fingerprint.
public struct ConstructionShape: Hashable, Sendable {

    public struct Argument: Hashable, Sendable {
        /// `nil` for positional / unlabeled arguments; otherwise the
        /// label as written in source.
        public let label: String?
        public let kind: ParameterizedValue.Kind

        public init(label: String?, kind: ParameterizedValue.Kind) {
            self.label = label
            self.kind = kind
        }
    }

    /// Arguments in canonical (sorted-by-label-then-kind) order.
    public let arguments: [Argument]

    public init(arguments: [Argument]) {
        self.arguments = arguments.sorted { lhs, rhs in
            let lhsLabel = lhs.label ?? ""
            let rhsLabel = rhs.label ?? ""
            if lhsLabel != rhsLabel {
                return lhsLabel < rhsLabel
            }
            return lhs.kind.sortKey < rhs.kind.sortKey
        }
    }

    /// String key that orders shapes for stable entry-list sorting.
    /// Internal — consumers should compare `ConstructionShape` values
    /// directly, not reach for the key.
    var canonicalLabelKey: String {
        arguments
            .map { "\($0.label ?? "")(\($0.kind.sortKey))" }
            .joined(separator: ",")
    }
}

/// One entry in a `ConstructionRecord` — all observed sites that
/// constructed `typeName` with the same `shape` fingerprint.
/// `siteCount == observedLiterals.count` always; the redundant field
/// is kept for clarity at consumer sites.
public struct ConstructionRecordEntry: Sendable {
    public let typeName: String
    public let shape: ConstructionShape
    public let siteCount: Int
    /// One row per observed call site, in visit order. Each row's
    /// length matches `shape.arguments.count` and the per-position
    /// literal text matches the canonical-sorted argument at the same
    /// position in `shape.arguments`. Preserved so M4.3's mock
    /// synthesizer (per OD #5 default `(a)`) can fall back to
    /// observed-literal generators if the user-extension path ever
    /// wants them — through M4 the field is informational.
    public let observedLiterals: [[String]]

    public init(
        typeName: String,
        shape: ConstructionShape,
        siteCount: Int,
        observedLiterals: [[String]]
    ) {
        self.typeName = typeName
        self.shape = shape
        self.siteCount = siteCount
        self.observedLiterals = observedLiterals
    }
}

/// Corpus-wide aggregation of `T(...)` constructor sites observed
/// across `[TestMethodSummary]`. M4.3's mock synthesizer queries this
/// for the §13 ≥3-site dominant-shape rule.
public struct ConstructionRecord: Sendable {

    public let entries: [ConstructionRecordEntry]

    public init(entries: [ConstructionRecordEntry]) {
        self.entries = entries
    }

    /// All entries for `typeName` (zero, one, or many — many = the
    /// type was constructed with multiple distinct shape fingerprints
    /// across the corpus). M4.3's synthesizer applies the
    /// "single dominant shape with siteCount ≥ 3" rule on top of this
    /// query.
    public func entries(for typeName: String) -> [ConstructionRecordEntry] {
        entries.filter { $0.typeName == typeName }
    }
}

// MARK: - Visitor

private final class ConstructionVisitor: SyntaxVisitor {

    struct Site {
        let typeName: String
        let shape: ConstructionShape
        let literals: [String]
    }

    private(set) var sites: [Site] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let typeName = constructorTypeName(of: node.calledExpression) else {
            return .visitChildren
        }
        guard let (shape, literals) = fingerprint(arguments: node.arguments) else {
            return .visitChildren
        }
        sites.append(Site(typeName: typeName, shape: shape, literals: literals))
        return .visitChildren
    }

    /// Returns the type name when `expr` is a bare type-shaped
    /// identifier — same UpperCamelCase rule M4.0 uses for the
    /// scanner's bare-constructor recovery.
    private func constructorTypeName(of expr: ExprSyntax) -> String? {
        guard let ref = expr.as(DeclReferenceExprSyntax.self) else {
            return nil
        }
        let name = ref.baseName.text
        guard let first = name.first, first.isLetter, first.isUppercase else {
            return nil
        }
        return name
    }

    /// Build a `ConstructionShape` + parallel literal-text row from
    /// the call's argument list. Returns `nil` when *any* argument
    /// fails literal-kind classification (non-literal exprs are
    /// unfingerprintable; the conservative posture skips the entire
    /// call rather than recording a partial shape).
    private func fingerprint(
        arguments: LabeledExprListSyntax
    ) -> (ConstructionShape, [String])? {
        var pairs: [ArgumentPair] = []
        for argument in arguments {
            guard let kind = literalKind(of: argument.expression) else {
                return nil
            }
            pairs.append(ArgumentPair(
                label: argument.label?.text,
                kind: kind,
                literal: argument.expression.trimmedDescription
            ))
        }
        // Sort pairs by (label, kind) so the fingerprint is
        // label-order-independent. ConstructionShape's init also sorts
        // its argument list — sorting here too keeps the literal row
        // aligned with the post-sort argument positions.
        pairs.sort { lhs, rhs in
            let lhsLabel = lhs.label ?? ""
            let rhsLabel = rhs.label ?? ""
            if lhsLabel != rhsLabel {
                return lhsLabel < rhsLabel
            }
            return lhs.kind.sortKey < rhs.kind.sortKey
        }
        let shape = ConstructionShape(
            arguments: pairs.map { ConstructionShape.Argument(label: $0.label, kind: $0.kind) }
        )
        let literals = pairs.map(\.literal)
        return (shape, literals)
    }

    private struct ArgumentPair {
        let label: String?
        let kind: ParameterizedValue.Kind
        let literal: String
    }

    /// Same kind-detection rule the M1 slicer applies — kept inline
    /// here rather than promoted to a shared helper because the rule
    /// is small and Slicer's helper is intentionally `private static`
    /// (its scope is the slicer's parameterized-value collection).
    private func literalKind(of expr: ExprSyntax) -> ParameterizedValue.Kind? {
        if expr.is(IntegerLiteralExprSyntax.self) {
            return .integer
        }
        if expr.is(StringLiteralExprSyntax.self) {
            return .string
        }
        if expr.is(BooleanLiteralExprSyntax.self) {
            return .boolean
        }
        if expr.is(FloatLiteralExprSyntax.self) {
            return .float
        }
        return nil
    }
}

// MARK: - Sort key for ParameterizedValue.Kind

private extension ParameterizedValue.Kind {
    /// Stable sort key for fingerprint canonicalization. Order is
    /// arbitrary but fixed.
    var sortKey: Int {
        switch self {
        case .boolean: return 0
        case .float:   return 1
        case .integer: return 2
        case .string:  return 3
        }
    }
}
