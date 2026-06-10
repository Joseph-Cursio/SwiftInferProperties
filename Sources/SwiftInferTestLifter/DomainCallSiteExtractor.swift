import SwiftInferCore
import SwiftSyntax

/// TestLifter M10.1 — pure-function call-site extractor for the
/// round-trip pair's reverse-side function. Walks a `SlicedTestBody`'s
/// `setup` and `propertyRegion` items for every `FunctionCallExprSyntax`
/// whose trailing identifier matches `consumer`, classifies the first-
/// argument expression at each call, and yields the resulting
/// `[DomainCallSite]` for the M10.2 inferrer.
///
/// **Match by trailing identifier component only** — same posture as
/// `AttributeScanner` for `@Discoverable`. `decode(x)`, `Codec.decode(x)`,
/// and `someObj.decode(x)` all match `consumer == "decode"`.
///
/// **Hard contract (PRD §15):** never throws. Bodies with no recognized
/// assertion / no consumer call sites produce an empty result.
///
/// The terminal assertion's argument expressions are subtrees of the
/// last `propertyRegion` item, so walking `propertyRegion` already
/// covers them — the extractor does NOT walk `assertion.arguments`
/// separately to avoid double-capturing a `decode(...)` written inline
/// inside `XCTAssertEqual(...)` / `#expect(...)`.
///
/// Per the M10 plan, location info is intentionally NOT carried on
/// `DomainCallSite`; the M10.2 inferrer only needs the classification
/// list to decide homogeneity. If diagnostics need source locations
/// later, the field can be added without breaking the inferrer's
/// surface (Equatable on the existing fields stays stable).
public enum DomainCallSiteExtractor {

    public static func extract(consumer: String, in slice: SlicedTestBody) -> [DomainCallSite] {
        let visitor = CallSiteVisitor(consumer: consumer)
        for item in slice.setup {
            visitor.walk(item)
        }
        for item in slice.propertyRegion {
            visitor.walk(item)
        }
        return visitor.sites
    }
}

private final class CallSiteVisitor: SyntaxVisitor {

    let consumer: String
    var sites: [DomainCallSite] = []

    init(consumer: String) {
        self.consumer = consumer
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.calledExpression.trailingIdentifierName == consumer else {
            return .visitChildren
        }
        guard let firstArg = node.arguments.first else {
            sites.append(DomainCallSite(argument: .other))
            return .visitChildren
        }
        sites.append(DomainCallSite(argument: classify(firstArg.expression)))
        return .visitChildren
    }

    private func classify(_ expr: ExprSyntax) -> ArgumentClassification {
        if let call = expr.as(FunctionCallExprSyntax.self),
           let producer = call.calledExpression.trailingIdentifierName {
            return .callOutput(producerName: producer)
        }
        if let ident = expr.as(DeclReferenceExprSyntax.self) {
            return .identifier(name: ident.baseName.text)
        }
        return .other
    }
}
