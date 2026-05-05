import SwiftSyntax

/// TestLifter M10.3 — corpus-wide aggregation pass that walks each
/// `SlicedTestBody` once and produces (a) `[String: [DomainCallSite]]`
/// keyed by the consumer function's trailing-identifier name, and
/// (b) `[String: ArgumentClassification]` from the slice's setup region
/// `let <name> = <expr>` bindings (used by `DomainInferrer.infer(...)`
/// to resolve `.identifier(name:)` sites).
///
/// One pass over the slice produces both maps so the M10.3 pipeline
/// wiring doesn't pay a second visitor traversal per slice.
///
/// **Hard contract (PRD §15):** never throws. Bodies with no call sites
/// or setup bindings produce empty maps.
public enum DomainCorpusScanner {

    public struct SliceArtifacts: Sendable, Equatable {
        public let callSitesByConsumer: [String: [DomainCallSite]]
        public let setupBindings: [String: ArgumentClassification]

        public init(
            callSitesByConsumer: [String: [DomainCallSite]],
            setupBindings: [String: ArgumentClassification]
        ) {
            self.callSitesByConsumer = callSitesByConsumer
            self.setupBindings = setupBindings
        }

        public static let empty = SliceArtifacts(callSitesByConsumer: [:], setupBindings: [:])
    }

    public static func artifacts(in slice: SlicedTestBody) -> SliceArtifacts {
        let visitor = ScannerVisitor(viewMode: .sourceAccurate)
        for item in slice.setup {
            visitor.walk(item)
        }
        for item in slice.propertyRegion {
            visitor.walk(item)
        }
        // Pre-resolve `.identifier` site classifications using the
        // slice's own setup bindings. Resolution is intra-slice only
        // per the M10 plan's narrowed scope (one test's `x` isn't
        // another test's `x`); doing it here means the corpus-merge
        // step (`mergeCallSites`) is safe to flatten across slices.
        // Identifier sites that fail to resolve degrade to `.other`
        // and become outliers per PRD §3.5.
        let resolved = visitor.callSitesByConsumer.mapValues { sites in
            sites.map { site in
                DomainCallSite(
                    argument: resolveClassification(site.argument, in: visitor.setupBindings)
                )
            }
        }
        return SliceArtifacts(
            callSitesByConsumer: resolved,
            setupBindings: visitor.setupBindings
        )
    }

    /// Transitively resolve a `.identifier(name:)` classification
    /// through `bindings` until a non-identifier is reached or a 5-hop
    /// depth limit guards against cycles. Cycles + missing names
    /// degrade to `.other`. Mirrors `DomainInferrer.resolve(...)`'s
    /// hop limit + cycle posture exactly so corpus-resolved sites
    /// match what the inferrer would produce on its own.
    private static func resolveClassification(
        _ classification: ArgumentClassification,
        in bindings: [String: ArgumentClassification],
        depth: Int = 0
    ) -> ArgumentClassification {
        guard depth < 5 else { return .other }
        guard case let .identifier(name) = classification else { return classification }
        guard let resolved = bindings[name] else { return .other }
        return resolveClassification(resolved, in: bindings, depth: depth + 1)
    }

    /// Merge per-slice artifacts into a corpus-wide call-site map. Setup
    /// bindings stay per-slice (resolution is intra-slice only per the
    /// M10 plan's narrowed scope) — the caller threads `setupBindings`
    /// through `[LiftedOrigin: ...]` style if needed.
    public static func mergeCallSites(
        _ artifactsList: [SliceArtifacts]
    ) -> [String: [DomainCallSite]] {
        var merged: [String: [DomainCallSite]] = [:]
        for artifacts in artifactsList {
            for (consumer, sites) in artifacts.callSitesByConsumer {
                merged[consumer, default: []].append(contentsOf: sites)
            }
        }
        return merged
    }
}

private final class ScannerVisitor: SyntaxVisitor {

    var callSitesByConsumer: [String: [DomainCallSite]] = [:]
    var setupBindings: [String: ArgumentClassification] = [:]

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let consumer = trailingIdentifier(of: node.calledExpression) else {
            return .visitChildren
        }
        let argument: ArgumentClassification = {
            guard let firstArg = node.arguments.first else {
                return .other
            }
            return classify(firstArg.expression)
        }()
        callSitesByConsumer[consumer, default: []].append(DomainCallSite(argument: argument))
        return .visitChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Single-binding `let <name> = <expr>` only — multi-binding
        // shapes (`let x = 1, y = 2`) and shadowed re-declarations are
        // out of scope for M10's narrowed identifier resolution.
        guard node.bindings.count == 1, let binding = node.bindings.first else {
            return .visitChildren
        }
        guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return .visitChildren
        }
        guard let initializer = binding.initializer?.value else {
            return .visitChildren
        }
        setupBindings[pattern.identifier.text] = classify(initializer)
        return .visitChildren
    }

    private func classify(_ expr: ExprSyntax) -> ArgumentClassification {
        if let call = expr.as(FunctionCallExprSyntax.self),
           let producer = trailingIdentifier(of: call.calledExpression) {
            return .callOutput(producerName: producer)
        }
        if let ident = expr.as(DeclReferenceExprSyntax.self) {
            return .identifier(name: ident.baseName.text)
        }
        return .other
    }

    private func trailingIdentifier(of expr: ExprSyntax) -> String? {
        if let ident = expr.as(DeclReferenceExprSyntax.self) {
            return ident.baseName.text
        }
        if let member = expr.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }
}
