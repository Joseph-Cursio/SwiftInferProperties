import Foundation
import SwiftEffectInference
import SwiftParser
import SwiftSyntax

@testable import SwiftInferCore

/// The frozen taxonomy and the re-derived refuters for
/// `PurityRefutationCensusMeasuredTests`. Split out only for the 400-line file
/// cap; the reasoning that governs both lives in that suite's header.
extension PurityRefutationCensusMeasuredTests {

    /// One reason `SoundPurity.verdict(for:)` can answer `.refuted`, read off
    /// its `guard`s in order. A function may satisfy several — they are
    /// collected as a *set*, never reduced to a "primary", because the two
    /// body-level refuters share a single `guard` and the code therefore states
    /// no precedence between them.
    enum RefutationCause: String, CaseIterable, Comparable {
        /// `ReducerPurityAnalyzer` refuted: a TCA/concurrency effect signal
        /// (`Effect` / `Task` / `await` / `.run` / `.send` / …) or a write to
        /// static or `Self` state. **Witness** — it names the construct.
        case reducerEffect

        /// No body to inspect. **Ignorance, inert.**
        case noBody

        /// The signature declares `async`. **Witness.**
        case asyncSignature

        /// A side-effect or nondeterminism marker token appears in the body.
        /// **Witness.**
        case marker

        /// A force-unwrap, `try!`, `as!`, or a trap call. **Witness.**
        case nonTotal

        /// `throws`, and the body `try`s into a callee this leaf cannot see.
        /// **Ignorance, actionable** — there is a callee to name.
        case propagatedTry

        /// Does this cause point at something in the source?
        var isWitness: Bool {
            switch self {
            case .reducerEffect, .asyncSignature, .marker, .nonTotal: return true
            case .noBody, .propagatedTry: return false
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The refuters, re-derived from `PurityInferrer` because they are `private`
    /// there. Guarded by `verdictAgreesWithSoundPurity` over the whole corpus.
    struct Attributor {
        /// `PurityInferrer.sideEffectMarkers`.
        static let sideEffectMarkers: Set<String> = [
            "print", "NSLog", "FileManager", "URLSession", "UserDefaults",
            "NotificationCenter", "DispatchQueue"
        ]

        /// `PurityInferrer.nondeterministicMarkers`.
        static let nondeterministicMarkers: Set<String> = [
            "arc4random", "arc4random_uniform", "drand48", "CFAbsoluteTimeGetCurrent",
            "random", "randomElement", "shuffled",
            "Date", "UUID"
        ]

        /// Injected so the control can truncate it.
        let markers: Set<String>

        init(markers: Set<String> = sideEffectMarkers.union(nondeterministicMarkers)) {
            self.markers = markers
        }

        /// Every cause that holds of `function`, independent of the order the
        /// real implementation would short-circuit in.
        func causes(of function: FunctionDeclSyntax) -> Set<RefutationCause> {
            var causes: Set<RefutationCause> = []
            if ReducerPurityAnalyzer.analyze(function) != .pure { causes.insert(.reducerEffect) }
            guard let body = function.body else {
                causes.insert(.noBody)
                return causes
            }
            if function.signature.effectSpecifiers?.asyncSpecifier != nil {
                causes.insert(.asyncSignature)
            }
            if hasMarker(in: body) { causes.insert(.marker) }
            if !isTotal(body) { causes.insert(.nonTotal) }
            if function.signature.effectSpecifiers?.throwsClause != nil, sawTry(in: body) {
                causes.insert(.propagatedTry)
            }
            return causes
        }

        /// The verdict these causes imply, re-assembled in
        /// `SoundPurity.verdict(for:)`'s exact order. Compared against the real
        /// answer on every function in the corpus — that comparison is the whole
        /// warrant for the replication above.
        func reassembledVerdict(of function: FunctionDeclSyntax) -> PurityVerdict {
            guard ReducerPurityAnalyzer.analyze(function) == .pure else { return .refuted }
            guard let body = function.body else { return .refuted }
            guard function.signature.effectSpecifiers?.asyncSpecifier == nil else { return .refuted }
            guard !hasMarker(in: body), isTotal(body) else { return .refuted }
            guard function.signature.effectSpecifiers?.throwsClause != nil else { return .pure }
            return sawTry(in: body) ? .refuted : .pureButPartial
        }

        private func hasMarker(in body: CodeBlockSyntax) -> Bool {
            body.tokens(viewMode: .sourceAccurate).contains { markers.contains($0.text) }
        }

        private func isTotal(_ body: CodeBlockSyntax) -> Bool {
            let checker = CensusTotalityChecker(viewMode: .sourceAccurate)
            checker.walk(body)
            return checker.isTotal
        }

        private func sawTry(in body: CodeBlockSyntax) -> Bool {
            let checker = CensusTryChecker(viewMode: .sourceAccurate)
            checker.walk(body)
            return checker.sawTry
        }
    }
}

// MARK: - Replicated checkers

/// `PurityInferrer.TotalityChecker`, re-derived. See the suite header for why a
/// copy here is safe.
final class CensusTotalityChecker: SyntaxVisitor {
    private(set) var isTotal = true

    private static let trapFunctions: Set<String> = [
        "fatalError", "preconditionFailure", "precondition",
        "assert", "assertionFailure"
    ]

    override func visit(_: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
        isTotal = false
        return .skipChildren
    }

    override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
        if node.questionOrExclamationMark?.text == "!" { isTotal = false }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let callee = node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text,
           Self.trapFunctions.contains(callee) {
            isTotal = false
        }
        return .visitChildren
    }
}

/// `PurityInferrer.TryExpressionChecker`, re-derived.
final class CensusTryChecker: SyntaxVisitor {
    private(set) var sawTry = false

    override func visit(_: TryExprSyntax) -> SyntaxVisitorContinueKind {
        sawTry = true
        return .skipChildren
    }
}

/// Collects function decls with `FunctionScannerVisitor`'s traversal rules:
/// nested functions and protocol requirements are both out of the population the
/// shipped scan summarises.
final class CensusFunctionCollector: SyntaxVisitor {
    private(set) var functions: [FunctionDeclSyntax] = []
    /// Accessor blocks by property name, for the computed-property half. Keyed
    /// by name rather than re-derived from `makeSummary(fromComputedProperty:)`'s
    /// filter — the caller intersects with the shipped scan's own names and
    /// asserts the intersection is total, so a divergence is reported rather
    /// than silently narrowing the population.
    private(set) var accessorsByName: [String: AccessorBlockSyntax] = [:]

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functions.append(node)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        for binding in node.bindings {
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
               let accessor = binding.accessorBlock {
                accessorsByName[pattern.identifier.text] = accessor
            }
        }
        return .visitChildren
    }

    override func visit(_: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
